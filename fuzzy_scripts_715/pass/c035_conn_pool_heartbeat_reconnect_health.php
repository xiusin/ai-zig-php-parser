<?php
// 极度混搭: 连接池管理 + 心跳检测 + 断线重连 + 健康检查 + 超时退避
echo "=== c035: ConnectionPool + Heartbeat + Reconnect + HealthCheck ===\n\n";

class Connection {
    private static int $nextId = 1;
    public readonly int $id;
    private string $host;
    private int $port;
    private string $state = 'disconnected';
    private int $createdAt;
    private int $lastActivity;
    private int $totalRequests = 0;

    public function __construct(string $host, int $port) {
        $this->id = self::$nextId++;
        $this->host = $host;
        $this->port = $port;
        $this->createdAt = 1;
        $this->lastActivity = 1;
    }

    public function connect(): bool {
        $this->state = 'connecting';
        $this->state = 'connected';
        $this->lastActivity = 1;
        return true;
    }

    public function disconnect(): void {
        $this->state = 'disconnected';
    }

    public function execute(string $query): array {
        if ($this->state !== 'connected') {
            throw new RuntimeException("Connection {$this->id} not connected");
        }
        $this->totalRequests++;
        $this->lastActivity = 1;
        return ['rows' => [$query], 'affected' => 1, 'conn_id' => $this->id];
    }

    public function isHealthy(): bool {
        return $this->state === 'connected';
    }

    public function getIdleTime(int $now): int {
        return $now - $this->lastActivity;
    }

    public function getStats(): array {
        return [
            'id' => $this->id,
            'host' => $this->host,
            'port' => $this->port,
            'state' => $this->state,
            'requests' => $this->totalRequests,
            'age' => 1 - $this->createdAt,
        ];
    }

    public function getState(): string { return $this->state; }
    public function getHost(): string { return $this->host; }
    public function getPort(): int { return $this->port; }
}

class HealthChecker {
    private array $checks = [];
    private array $results = [];

    public function addCheck(string $name, callable $fn): self {
        $this->checks[$name] = $fn;
        return $this;
    }

    public function runAll(): array {
        $this->results = [];
        foreach ($this->checks as $name => $fn) {
            try {
                $result = $fn();
                $this->results[$name] = ['status' => 'pass', 'detail' => $result];
            } catch (Exception $e) {
                $this->results[$name] = ['status' => 'fail', 'detail' => $e->getMessage()];
            }
        }
        return $this->results;
    }

    public function isHealthy(): bool {
        foreach ($this->results as $r) {
            if ($r['status'] !== 'pass') return false;
        }
        return true;
    }

    public function getResults(): array {
        return $this->results;
    }
}

class ExponentialBackoff {
    private int $baseDelay;
    private int $maxDelay;
    private int $maxRetries;
    private int $attempts = 0;

    public function __construct(int $baseDelay = 100, int $maxDelay = 5000, int $maxRetries = 5) {
        $this->baseDelay = $baseDelay;
        $this->maxDelay = $maxDelay;
        $this->maxRetries = $maxRetries;
    }

    public function nextDelay(): int {
        if ($this->attempts >= $this->maxRetries) return -1;
        $delay = min($this->baseDelay * pow(2, $this->attempts), $this->maxDelay);
        $this->attempts++;
        return (int)$delay;
    }

    public function shouldRetry(): bool {
        return $this->attempts < $this->maxRetries;
    }

    public function reset(): void {
        $this->attempts = 0;
    }

    public function getAttempts(): int {
        return $this->attempts;
    }
}

class ManagedConnectionPool {
    private array $connections = [];
    private array $available = [];
    private array $inUse = [];
    private int $maxSize;
    private int $minIdle;
    private int $maxIdleTime;
    private HealthChecker $healthChecker;
    private array $stats = ['created' => 0, 'reused' => 0, 'failed' => 0, 'evicted' => 0];
    private string $host;
    private int $port;

    public function __construct(string $host, int $port, int $maxSize = 10, int $minIdle = 2, int $maxIdleTime = 300) {
        $this->host = $host;
        $this->port = $port;
        $this->maxSize = $maxSize;
        $this->minIdle = $minIdle;
        $this->maxIdleTime = $maxIdleTime;
        $this->healthChecker = new HealthChecker();
    }

    public function initialize(): void {
        for ($i = 0; $i < $this->minIdle; $i++) {
            $conn = $this->createConnection();
            $this->available[$conn->id] = $conn;
        }
    }

    private function createConnection(): Connection {
        $conn = new Connection($this->host, $this->port);
        $conn->connect();
        $this->connections[$conn->id] = $conn;
        $this->stats['created']++;
        return $conn;
    }

    public function acquire(): Connection {
        if (!empty($this->available)) {
            $conn = array_pop($this->available);
            if ($conn->isHealthy()) {
                $this->inUse[$conn->id] = $conn;
                $this->stats['reused']++;
                return $conn;
            } else {
                $this->stats['evicted']++;
                unset($this->connections[$conn->id]);
            }
        }

        if (count($this->connections) < $this->maxSize) {
            $conn = $this->createConnection();
            $this->inUse[$conn->id] = $conn;
            return $conn;
        }

        $this->stats['failed']++;
        throw new RuntimeException("Pool exhausted");
    }

    public function release(Connection $conn): void {
        if (!isset($this->inUse[$conn->id])) return;
        unset($this->inUse[$conn->id]);
        if ($conn->isHealthy()) {
            $this->available[$conn->id] = $conn;
        } else {
            $this->stats['evicted']++;
            unset($this->connections[$conn->id]);
            $this->ensureMinIdle();
        }
    }

    private function ensureMinIdle(): void {
        $idleCount = count($this->available);
        for ($i = $idleCount; $i < $this->minIdle; $i++) {
            $conn = $this->createConnection();
            $this->available[$conn->id] = $conn;
        }
    }

    public function evictIdle(int $now): int {
        $evicted = 0;
        foreach ($this->available as $id => $conn) {
            if ($conn->getIdleTime($now) > $this->maxIdleTime) {
                $conn->disconnect();
                unset($this->available[$id], $this->connections[$id]);
                $evicted++;
            }
        }
        $this->stats['evicted'] += $evicted;
        $this->ensureMinIdle();
        return $evicted;
    }

    public function reconnectDead(Connection $conn): ?Connection {
        $backoff = new ExponentialBackoff(10, 100, 3);
        while ($backoff->shouldRetry()) {
            $delay = $backoff->nextDelay();
            if ($delay < 0) break;
            $conn->disconnect();
            $result = $conn->connect();
            if ($result) return $conn;
        }
        return null;
    }

    public function getStats(): array {
        return array_merge($this->stats, [
            'total' => count($this->connections),
            'available' => count($this->available),
            'inUse' => count($this->inUse),
            'maxSize' => $this->maxSize,
        ]);
    }

    public function healthCheck(): array {
        $this->healthChecker->addCheck('pool_size', fn() => count($this->connections) . " connections");
        $this->healthChecker->addCheck('available', fn() => count($this->available) . " available");
        $this->healthChecker->addCheck('capacity', function() {
            if (count($this->connections) > $this->maxSize) {
                throw new RuntimeException("Over capacity");
            }
            return "OK";
        });
        $this->healthChecker->runAll();
        return $this->healthChecker->getResults();
    }
}

// === 测试 ===

echo "--- Pool Initialization ---\n";
$pool = new ManagedConnectionPool('localhost', 3306, 5, 2, 100);
$pool->initialize();
echo "Stats: " . json_encode($pool->getStats()) . "\n";

echo "\n--- Acquire/Release ---\n";
$c1 = $pool->acquire();
$c2 = $pool->acquire();
$c3 = $pool->acquire();
echo "Acquired 3 connections: #{$c1->id}, #{$c2->id}, #{$c3->id}\n";
echo "Stats: " . json_encode($pool->getStats()) . "\n";

$result = $c1->execute("SELECT * FROM users");
echo "Query result: " . json_encode($result) . "\n";

$pool->release($c2);
echo "After release #{$c2->id}: " . json_encode($pool->getStats()) . "\n";

$c4 = $pool->acquire();
echo "Reacquire (should reuse #{$c2->id}): #{$c4->id}\n";

echo "\n--- Pool Exhaustion ---\n";
try {
    $c5 = $pool->acquire();
    $c6 = $pool->acquire();
    echo "Got #{$c5->id} and #{$c6->id}\n";
    $c7 = $pool->acquire();
} catch (RuntimeException $e) {
    echo "Expected: " . $e->getMessage() . "\n";
}

echo "\n--- Release All ---\n";
$pool->release($c1);
$pool->release($c3);
$pool->release($c4);
$pool->release($c5);
$pool->release($c6);
echo "Stats: " . json_encode($pool->getStats()) . "\n";

echo "\n--- Idle Eviction ---\n";
$evicted = $pool->evictIdle(1000);
echo "Evicted: $evicted\n";
echo "Stats: " . json_encode($pool->getStats()) . "\n";

echo "\n--- Health Check ---\n";
$health = $pool->healthCheck();
foreach ($health as $name => $result) {
    echo "  $name: {$result['status']} ({$result['detail']})\n";
}

echo "\n--- Connection Stats ---\n";
foreach ($pool->getStats() as $k => $v) {
    echo "  $k: $v\n";
}

echo "\n--- Reconnect with Backoff ---\n";
$dead = $pool->acquire();
$dead->disconnect();
echo "Dead conn state: " . $dead->getState() . "\n";
$reconnected = $pool->reconnectDead($dead);
echo "Reconnected: " . ($reconnected !== null ? "YES state=" . $reconnected->getState() : "NO") . "\n";
$pool->release($dead);

echo "\n=== c035 Done ===\n";
