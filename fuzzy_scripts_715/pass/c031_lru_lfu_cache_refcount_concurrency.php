<?php
// 极度混搭: LRU/LFU缓存淘汰 + 时间窗口 + 引用计数 + 并发安全模拟
echo "=== c031: LRU/LFU Cache + TimeWindow + RefCount + Concurrency ===\n\n";

class LRUCache {
    private int $capacity;
    private array $cache = [];
    private array $accessOrder = [];
    private int $hits = 0;
    private int $misses = 0;
    private int $evictions = 0;

    public function __construct(int $capacity) {
        $this->capacity = $capacity;
    }

    public function get(string $key): mixed {
        if (!isset($this->cache[$key])) {
            $this->misses++;
            return null;
        }
        $this->hits++;
        // Move to end (most recently used)
        unset($this->accessOrder[$key]);
        $this->accessOrder[$key] = true;
        return $this->cache[$key];
    }

    public function put(string $key, mixed $value): void {
        if (isset($this->cache[$key])) {
            $this->cache[$key] = $value;
            unset($this->accessOrder[$key]);
            $this->accessOrder[$key] = true;
            return;
        }

        if (count($this->cache) >= $this->capacity) {
            $evictKey = array_key_first($this->accessOrder);
            unset($this->cache[$evictKey], $this->accessOrder[$evictKey]);
            $this->evictions++;
        }

        $this->cache[$key] = $value;
        $this->accessOrder[$key] = true;
    }

    public function stats(): array {
        return [
            'size' => count($this->cache),
            'capacity' => $this->capacity,
            'hits' => $this->hits,
            'misses' => $this->misses,
            'evictions' => $this->evictions,
            'hit_rate' => $this->hits + $this->misses > 0
                ? round($this->hits / ($this->hits + $this->misses) * 100, 2)
                : 0,
        ];
    }

    public function keys(): array {
        return array_keys($this->cache);
    }
}

class LFUCache {
    private int $capacity;
    private array $cache = [];
    private array $freq = [];
    private array $freqLists = [];
    private int $minFreq = 0;

    public function __construct(int $capacity) {
        $this->capacity = $capacity;
    }

    public function get(string $key): mixed {
        if (!isset($this->cache[$key])) return null;

        $oldFreq = $this->freq[$key];
        unset($this->freqLists[$oldFreq][$key]);

        $newFreq = $oldFreq + 1;
        $this->freq[$key] = $newFreq;
        $this->freqLists[$newFreq][$key] = true;

        if ($oldFreq === $this->minFreq && empty($this->freqLists[$oldFreq])) {
            $this->minFreq = $newFreq;
        }

        return $this->cache[$key];
    }

    public function put(string $key, mixed $value): void {
        if ($this->capacity <= 0) return;

        if (isset($this->cache[$key])) {
            $this->cache[$key] = $value;
            $this->get($key); // Update frequency
            return;
        }

        if (count($this->cache) >= $this->capacity) {
            $evictKey = array_key_first($this->freqLists[$this->minFreq]);
            unset($this->cache[$evictKey], $this->freq[$evictKey], $this->freqLists[$this->minFreq][$evictKey]);
        }

        $this->cache[$key] = $value;
        $this->freq[$key] = 1;
        $this->freqLists[1][$key] = true;
        $this->minFreq = 1;
    }

    public function size(): int {
        return count($this->cache);
    }

    public function getFreqs(): array {
        return $this->freq;
    }
}

class TimeWindowCounter {
    private int $windowMs;
    private array $events = [];

    public function __construct(int $windowMs = 1000) {
        $this->windowMs = $windowMs;
    }

    public function record(int $timestamp, mixed $data = null): void {
        $this->events[] = ['ts' => $timestamp, 'data' => $data];
        $this->cleanup($timestamp);
    }

    public function count(int $timestamp): int {
        $this->cleanup($timestamp);
        return count($this->events);
    }

    public function getEvents(int $timestamp): array {
        $this->cleanup($timestamp);
        return $this->events;
    }

    private function cleanup(int $currentTs): void {
        $threshold = $currentTs - $this->windowMs;
        $this->events = array_values(array_filter($this->events, fn($e) => $e['ts'] > $threshold));
    }
}

class RefCountedValue {
    private mixed $value;
    private int $refCount = 0;
    private int $weakRefs = 0;

    public function __construct(mixed $value) {
        $this->value = $value;
    }

    public function acquire(): void {
        $this->refCount++;
    }

    public function release(): bool {
        if ($this->refCount > 0) {
            $this->refCount--;
        }
        return $this->refCount === 0;
    }

    public function addWeakRef(): void {
        $this->weakRefs++;
    }

    public function removeWeakRef(): void {
        if ($this->weakRefs > 0) $this->weakRefs--;
    }

    public function getValue(): mixed {
        return $this->value;
    }

    public function getRefCount(): int {
        return $this->refCount;
    }

    public function getWeakRefCount(): int {
        return $this->weakRefs;
    }

    public function isAlive(): bool {
        return $this->refCount > 0;
    }
}

class ConcurrentCache {
    private array $data = [];
    private bool $locked = false;
    private int $lockOwner = 0;
    private int $version = 0;

    private function acquireLock(int $threadId): bool {
        if ($this->locked && $this->lockOwner !== $threadId) return false;
        $this->locked = true;
        $this->lockOwner = $threadId;
        return true;
    }

    private function releaseLock(int $threadId): void {
        if ($this->lockOwner === $threadId) {
            $this->locked = false;
            $this->lockOwner = 0;
        }
    }

    public function get(string $key, int $threadId): mixed {
        if (!$this->acquireLock($threadId)) return 'LOCK_FAIL';
        try {
            return $this->data[$key] ?? null;
        } finally {
            $this->releaseLock($threadId);
        }
    }

    public function set(string $key, mixed $value, int $threadId): bool {
        if (!$this->acquireLock($threadId)) return false;
        try {
            $this->data[$key] = $value;
            $this->version++;
            return true;
        } finally {
            $this->releaseLock($threadId);
        }
    }

    public function getVersion(): int {
        return $this->version;
    }

    public function size(): int {
        return count($this->data);
    }
}

// === 测试 ===

echo "--- LRU Cache ---\n";
$lru = new LRUCache(3);
$lru->put('a', 1);
$lru->put('b', 2);
$lru->put('c', 3);
echo "get(a): " . $lru->get('a') . "\n";
$lru->put('d', 4); // Evicts 'b' (least recently used)
echo "get(b): " . var_export($lru->get('b'), true) . "\n";
echo "get(c): " . $lru->get('c') . "\n";
echo "Keys: " . implode(",", $lru->keys()) . "\n";
echo "Stats: " . json_encode($lru->stats()) . "\n";

echo "\n--- LFU Cache ---\n";
$lfu = new LFUCache(3);
$lfu->put('a', 1);
$lfu->put('b', 2);
$lfu->put('c', 3);
$lfu->get('a');
$lfu->get('a');
$lfu->get('b');
$lfu->put('d', 4); // Evicts 'c' (least frequently used)
echo "get(a): " . $lfu->get('a') . "\n";
echo "get(b): " . $lfu->get('b') . "\n";
echo "get(c): " . var_export($lfu->get('c'), true) . "\n";
echo "get(d): " . $lfu->get('d') . "\n";
echo "Size: " . $lfu->size() . "\n";
echo "Freqs: " . json_encode($lfu->getFreqs()) . "\n";

echo "\n--- Time Window Counter ---\n";
$twc = new TimeWindowCounter(10);
$twc->record(1, 'a');
$twc->record(5, 'b');
$twc->record(8, 'c');
echo "Count at t=8: " . $twc->count(8) . "\n";
$twc->record(12, 'd');
echo "Count at t=12: " . $twc->count(12) . "\n";
echo "Events at t=12: " . json_encode(array_column($twc->getEvents(12), 'data')) . "\n";

echo "\n--- Reference Counting ---\n";
$rc = new RefCountedValue("shared_data");
$rc->acquire();
$rc->acquire();
$rc->addWeakRef();
echo "Refs: " . $rc->getRefCount() . " Weak: " . $rc->getWeakRefCount() . "\n";
echo "Alive: " . var_export($rc->isAlive(), true) . "\n";
$rc->release();
echo "After release: refs=" . $rc->getRefCount() . " alive=" . var_export($rc->isAlive(), true) . "\n";
$rc->release();
echo "After 2nd release: refs=" . $rc->getRefCount() . " alive=" . var_export($rc->isAlive(), true) . "\n";

echo "\n--- Concurrent Cache (Lock Simulation) ---\n";
$cc = new ConcurrentCache();
echo "Set by thread 1: " . var_export($cc->set('key', 'val1', 1), true) . "\n";
echo "Get by thread 1: " . $cc->get('key', 1) . "\n";
echo "Get by thread 2 (should fail): " . var_export($cc->get('key', 2), true) . "\n";
echo "Set by thread 2 (should fail): " . var_export($cc->set('key2', 'val2', 2), true) . "\n";
echo "Version: " . $cc->getVersion() . "\n";

echo "\n=== c031 Done ===\n";
