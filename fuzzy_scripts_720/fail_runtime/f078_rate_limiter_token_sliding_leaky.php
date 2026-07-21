<?php
// 极度混搭: 限流器 + 令牌桶 + 滑动窗口 + 漏桶 + 分布式限流
echo "=== f078: Rate Limiter + TokenBucket + SlidingWindow ===\n";

class TokenBucket {
    private float $tokens;
    private float $lastRefill;

    public function __construct(
        private float $capacity,
        private float $refillRate,
    ) {
        $this->tokens = $capacity;
        $this->lastRefill = microtime(true);
    }

    private function refill(): void {
        $now = microtime(true);
        $elapsed = $now - $this->lastRefill;
        $this->tokens = min($this->capacity, $this->tokens + $elapsed * $this->refillRate);
        $this->lastRefill = $now;
    }

    public function tryConsume(int $tokens = 1): bool {
        $this->refill();
        if ($this->tokens >= $tokens) {
            $this->tokens -= $tokens;
            return true;
        }
        return false;
    }

    public function getTokens(): float { $this->refill(); return $this->tokens; }
}

class SlidingWindowLimiter {
    private array $requests = [];

    public function __construct(
        private int $maxRequests,
        private float $windowSeconds,
    ) {}

    public function tryAcquire(): bool {
        $now = microtime(true);
        $cutoff = $now - $this->windowSeconds;
        $this->requests = array_values(array_filter($this->requests, fn($t) => $t > $cutoff));
        if (count($this->requests) < $this->maxRequests) {
            $this->requests[] = $now;
            return true;
        }
        return false;
    }

    public function getCurrentCount(): int {
        $now = microtime(true);
        $cutoff = $now - $this->windowSeconds;
        return count(array_filter($this->requests, fn($t) => $t > $cutoff));
    }
}

class LeakyBucket {
    private float $water = 0;
    private float $lastLeak;

    public function __construct(
        private float $capacity,
        private float $leakRate,
    ) {
        $this->lastLeak = microtime(true);
    }

    private function leak(): void {
        $now = microtime(true);
        $elapsed = $now - $this->lastLeak;
        $this->water = max(0, $this->water - $elapsed * $this->leakRate);
        $this->lastLeak = $now;
    }

    public function tryAdd(float $amount = 1): bool {
        $this->leak();
        if ($this->water + $amount <= $this->capacity) {
            $this->water += $amount;
            return true;
        }
        return false;
    }

    public function getWater(): float { $this->leak(); return $this->water; }
}

class DistributedRateLimiter {
    private array $buckets = [];

    public function __construct(
        private int $globalLimit,
        private int $perClientLimit,
        private float $window = 1.0,
    ) {}

    public function check(string $clientId): array {
        if (!isset($this->buckets[$clientId])) {
            $this->buckets[$clientId] = ['count' => 0, 'window_start' => microtime(true)];
        }
        $bucket = &$this->buckets[$clientId];
        $now = microtime(true);
        if ($now - $bucket['window_start'] > $this->window) {
            $bucket['count'] = 0;
            $bucket['window_start'] = $now;
        }
        $globalCount = array_sum(array_map(fn($b) => $b['count'], $this->buckets));
        $allowed = $bucket['count'] < $this->perClientLimit && $globalCount < $this->globalLimit;
        if ($allowed) $bucket['count']++;
        return [
            'allowed' => $allowed,
            'client_count' => $bucket['count'],
            'client_limit' => $this->perClientLimit,
            'global_count' => $globalCount,
            'global_limit' => $this->globalLimit,
        ];
    }
}

// 测试
echo "--- Token Bucket ---\n";
$bucket = new TokenBucket(5, 2); // 容量5，每秒补充2
$allowed = 0; $denied = 0;
for ($i = 0; $i < 10; $i++) {
    if ($bucket->tryConsume()) $allowed++; else $denied++;
}
echo "First burst: allowed=$allowed denied=$denied (capacity=5)\n";
echo "Tokens remaining: " . number_format($bucket->getTokens(), 2) . "\n";

usleep(500000); // 等0.5秒
echo "After 0.5s, tokens: " . number_format($bucket->getTokens(), 2) . " (should ~1 more)\n";
echo "Consume 1: " . var_export($bucket->tryConsume(), true) . "\n";

echo "\n--- Sliding Window ---\n";
$sw = new SlidingWindowLimiter(5, 1.0);
$allowed = 0; $denied = 0;
for ($i = 0; $i < 8; $i++) {
    if ($sw->tryAcquire()) $allowed++; else $denied++;
}
echo "8 rapid requests: allowed=$allowed denied=$denied (limit=5/1s)\n";
echo "Current count: " . $sw->getCurrentCount() . "\n";

echo "\n--- Leaky Bucket ---\n";
$lb = new LeakyBucket(3, 2); // 容量3，每秒漏2
$allowed = 0; $denied = 0;
for ($i = 0; $i < 6; $i++) {
    if ($lb->tryAdd()) $allowed++; else $denied++;
}
echo "6 rapid adds: allowed=$allowed denied=$denied (capacity=3)\n";
echo "Water: " . number_format($lb->getWater(), 2) . "\n";

usleep(500000);
echo "After 0.5s, water: " . number_format($lb->getWater(), 2) . " (should ~1 less)\n";
echo "Add 1: " . var_export($lb->tryAdd(), true) . "\n";

echo "\n--- Distributed Rate Limiter ---\n";
$drl = new DistributedRateLimiter(10, 3, 1.0);
echo "Global limit=10, per-client=3\n";
for ($client = 1; $client <= 4; $client++) {
    $results = [];
    for ($i = 0; $i < 4; $i++) {
        $r = $drl->check("client-$client");
        $results[] = $r['allowed'] ? 'Y' : 'N';
    }
    echo "  client-$client: " . implode(' ', $results) . "\n";
}

echo "\n--- API Simulation ---\n";
echo "Simulating 20 API calls from 3 clients:\n";
$api = new DistributedRateLimiter(15, 5, 1.0);
$stats = ['allowed' => 0, 'denied' => 0];
$perClient = ['A' => ['Y' => 0, 'N' => 0], 'B' => ['Y' => 0, 'N' => 0], 'C' => ['Y' => 0, 'N' => 0]];
$clients = ['A', 'B', 'C'];
for ($i = 0; $i < 20; $i++) {
    $client = $clients[$i % 3];
    $r = $api->check("client-$client");
    if ($r['allowed']) { $stats['allowed']++; $perClient[$client]['Y']++; }
    else { $stats['denied']++; $perClient[$client]['N']++; }
}
echo "  Total: allowed={$stats['allowed']} denied={$stats['denied']}\n";
foreach ($perClient as $c => $s) {
    echo "  Client $c: allowed={$s['Y']} denied={$s['N']}\n";
}

echo "=== f078 Done ===\n";
