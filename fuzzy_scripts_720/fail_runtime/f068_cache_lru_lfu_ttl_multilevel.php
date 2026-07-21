<?php
// 极度混搭: 缓存系统 + LRU + LFU + TTL + 多级缓存 + 内存统计
echo "=== f068: Cache System + LRU + LFU + TTL + MultiLevel ===\n";

class CacheEntry {
    public function __construct(
        public mixed $value,
        public int $expireAt = 0,
        public int $createdAt = 0,
        public int $accessCount = 0,
        public int $lastAccess = 0,
    ) {}
}

class LRUCache {
    private array $cache = [];
    private array $accessOrder = [];

    public function __construct(private int $capacity) {}

    public function get(string $key): mixed {
        if (!isset($this->cache[$key])) return null;
        // 更新访问顺序
        $this->accessOrder = array_diff($this->accessOrder, [$key]);
        $this->accessOrder[] = $key;
        $this->cache[$key]->accessCount++;
        $this->cache[$key]->lastAccess = microtime(true);
        return $this->cache[$key]->value;
    }

    public function put(string $key, mixed $value, int $ttl = 0): void {
        if (isset($this->cache[$key])) {
            $this->cache[$key]->value = $value;
            $this->accessOrder = array_diff($this->accessOrder, [$key]);
            $this->accessOrder[] = $key;
            return;
        }
        if (count($this->cache) >= $this->capacity) {
            $evictKey = $this->accessOrder[0];
            unset($this->cache[$evictKey]);
            $this->accessOrder = array_slice($this->accessOrder, 1);
        }
        $expireAt = $ttl > 0 ? time() + $ttl : 0;
        $this->cache[$key] = new CacheEntry($value, $expireAt, time());
        $this->accessOrder[] = $key;
    }

    public function remove(string $key): void {
        unset($this->cache[$key]);
        $this->accessOrder = array_diff($this->accessOrder, [$key]);
    }

    public function stats(): array {
        $now = time();
        $expired = 0;
        foreach ($this->cache as $entry) {
            if ($entry->expireAt > 0 && $entry->expireAt < $now) $expired++;
        }
        return ['size' => count($this->cache), 'capacity' => $this->capacity, 'expired' => $expired];
    }

    public function cleanup(): int {
        $now = time();
        $removed = 0;
        foreach ($this->cache as $key => $entry) {
            if ($entry->expireAt > 0 && $entry->expireAt < $now) {
                $this->remove($key);
                $removed++;
            }
        }
        return $removed;
    }
}

class LFUCache {
    private array $cache = [];
    private array $freq = [];

    public function __construct(private int $capacity) {}

    public function get(string $key): mixed {
        if (!isset($this->cache[$key])) return null;
        $this->freq[$key]++;
        return $this->cache[$key];
    }

    public function put(string $key, mixed $value): void {
        if (count($this->cache) >= $this->capacity && !isset($this->cache[$key])) {
            $minKey = array_search(min($this->freq), $this->freq);
            unset($this->cache[$minKey], $this->freq[$minKey]);
        }
        $this->cache[$key] = $value;
        $this->freq[$key] = ($this->freq[$key] ?? 0) + 1;
    }

    public function stats(): array {
        return ['size' => count($this->cache), 'capacity' => $this->capacity];
    }
}

class MultiLevelCache {
    private array $levels = [];
    private array $stats = ['l1_hit' => 0, 'l2_hit' => 0, 'l3_hit' => 0, 'miss' => 0];

    public function __construct(LRUCache $l1, LRUCache $l2, LRUCache $l3) {
        $this->levels = [$l1, $l2, $l3];
    }

    public function get(string $key): mixed {
        foreach ($this->levels as $i => $cache) {
            $val = $cache->get($key);
            if ($val !== null) {
                $this->stats[match($i) {0 => 'l1_hit', 1 => 'l2_hit', 2 => 'l3_hit'}]++;
                // 回填上层
                for ($j = 0; $j < $i; $j++) {
                    $this->levels[$j]->put($key, $val);
                }
                return $val;
            }
        }
        $this->stats['miss']++;
        return null;
    }

    public function put(string $key, mixed $value, int $ttl = 0): void {
        $this->levels[0]->put($key, $value, $ttl);
    }

    public function getStats(): array { return $this->stats; }
}

// 测试
echo "--- LRU Cache ---\n";
$lru = new LRUCache(3);
$lru->put('a', 1);
$lru->put('b', 2);
$lru->put('c', 3);
echo "get a: " . $lru->get('a') . "\n";
echo "get b: " . $lru->get('b') . "\n";
$lru->put('d', 4); // c should be evicted
echo "get c: " . var_export($lru->get('c'), true) . " (evicted)\n";
echo "get d: " . $lru->get('d') . "\n";
echo "Stats: " . json_encode($lru->stats()) . "\n";

echo "\n--- LRU with TTL ---\n";
$lru2 = new LRUCache(10);
$lru2->put('temp', 'value', 1); // 1秒TTL
echo "get temp (immediate): " . $lru2->get('temp') . "\n";
sleep(2);
echo "get temp (after 2s): " . var_export($lru2->get('temp'), true) . "\n";
$cleaned = $lru2->cleanup();
echo "Cleaned up: $cleaned entries\n";

echo "\n--- LFU Cache ---\n";
$lfu = new LFUCache(3);
$lfu->put('x', 10);
$lfu->put('y', 20);
$lfu->put('z', 30);
$lfu->get('x'); $lfu->get('x'); // x freq=3
$lfu->get('y'); // y freq=2
$lfu->put('w', 40); // z (freq=1) should be evicted
echo "get x: " . $lfu->get('x') . "\n";
echo "get y: " . $lfu->get('y') . "\n";
echo "get z: " . var_export($lfu->get('z'), true) . " (evicted)\n";
echo "get w: " . $lfu->get('w') . "\n";
echo "Stats: " . json_encode($lfu->stats()) . "\n";

echo "\n--- Multi-Level Cache ---\n";
$l1 = new LRUCache(2);
$l2 = new LRUCache(4);
$l3 = new LRUCache(8);
$mlc = new MultiLevelCache($l1, $l2, $l3);

$mlc->put('key1', 'val1');
$mlc->put('key2', 'val2');
$mlc->put('key3', 'val3'); // key1 evicted from L1

echo "get key1: " . $mlc->get('key1') . "\n"; // miss L1, hit L2, backfill L1
echo "get key2: " . $mlc->get('key2') . "\n";
echo "get key3: " . $mlc->get('key3') . "\n";
echo "get key4 (miss): " . var_export($mlc->get('key4'), true) . "\n";
echo "Stats: " . json_encode($mlc->getStats()) . "\n";

echo "=== f068 Done ===\n";
