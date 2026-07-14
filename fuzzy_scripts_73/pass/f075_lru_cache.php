<?php
// LRU 缓存：双向链表+哈希表
echo "=== LRU Cache ===\n\n";

class LRUNode {
    public ?LRUNode $prev = null;
    public ?LRUNode $next = null;
    public function __construct(
        public string $key,
        public mixed $value
    ) {}
}

class LRUCache {
    private int $capacity;
    private array $map = [];
    private ?LRUNode $head = null;
    private ?LRUNode $tail = null;
    private int $size = 0;
    private array $stats = ['hits' => 0, 'misses' => 0, 'evictions' => 0];

    public function __construct(int $capacity) {
        $this->capacity = $capacity;
    }

    public function get(string $key): mixed {
        if (!isset($this->map[$key])) {
            $this->stats['misses']++;
            return null;
        }
        $node = $this->map[$key];
        $this->moveToHead($node);
        $this->stats['hits']++;
        return $node->value;
    }

    public function put(string $key, mixed $value): void {
        if (isset($this->map[$key])) {
            $node = $this->map[$key];
            $node->value = $value;
            $this->moveToHead($node);
            return;
        }
        $node = new LRUNode($key, $value);
        $this->map[$key] = $node;
        $this->addToHead($node);
        $this->size++;
        if ($this->size > $this->capacity) {
            $evicted = $this->tail;
            $this->removeNode($evicted);
            unset($this->map[$evicted->key]);
            $this->size--;
            $this->stats['evictions']++;
        }
    }

    public function delete(string $key): bool {
        if (!isset($this->map[$key])) return false;
        $this->removeNode($this->map[$key]);
        unset($this->map[$key]);
        $this->size--;
        return true;
    }

    public function has(string $key): bool { return isset($this->map[$key]); }

    private function addToHead(LRUNode $node): void {
        $node->prev = null;
        $node->next = $this->head;
        if ($this->head !== null) $this->head->prev = $node;
        $this->head = $node;
        if ($this->tail === null) $this->tail = $node;
    }

    private function removeNode(LRUNode $node): void {
        if ($node->prev !== null) $node->prev->next = $node->next;
        else $this->head = $node->next;
        if ($node->next !== null) $node->next->prev = $node->prev;
        else $this->tail = $node->prev;
    }

    private function moveToHead(LRUNode $node): void {
        if ($this->head === $node) return;
        $this->removeNode($node);
        $this->addToHead($node);
    }

    public function getSize(): int { return $this->size; }
    public function getStats(): array { return $this->stats; }
    public function getHitRate(): float {
        $total = $this->stats['hits'] + $this->stats['misses'];
        return $total === 0 ? 0.0 : $this->stats['hits'] / $total;
    }

    public function getKeys(): array {
        $keys = [];
        $node = $this->head;
        while ($node !== null) {
            $keys[] = $node->key;
            $node = $node->next;
        }
        return $keys;
    }
}

// === 测试 ===
echo "--- Basic Operations ---\n";
$cache = new LRUCache(3);
$cache->put('a', 1);
$cache->put('b', 2);
$cache->put('c', 3);

echo "Size: " . $cache->getSize() . "\n";
echo "Keys (LRU order): " . implode(' -> ', $cache->getKeys()) . "\n";
echo "get('a'): " . $cache->get('a') . "\n";
echo "Keys after get('a'): " . implode(' -> ', $cache->getKeys()) . "\n";

$cache->put('d', 4);
echo "After put('d'):\n";
echo "  Size: " . $cache->getSize() . "\n";
echo "  Keys: " . implode(' -> ', $cache->getKeys()) . "\n";
echo "  has('b'): " . ($cache->has('b') ? 'true' : 'false') . "\n";

$cache->put('a', 100);
echo "After update('a', 100): get('a') = " . $cache->get('a') . "\n";

// 统计测试
echo "\n--- Statistics ---\n";
$cache2 = new LRUCache(5);
$cache2->put('key1', 'value1');
$cache2->put('key2', 'value2');
$cache2->put('key3', 'value3');
$cache2->get('key1');
$cache2->get('key2');
$cache2->get('key4');
$cache2->put('key4', 'value4');
$cache2->get('key4');
$cache2->get('key5');
$cache2->get('key1');

echo "Stats: " . json_encode($cache2->getStats()) . "\n";
printf("Hit rate: %.2f%%\n", $cache2->getHitRate() * 100);

// LRU 顺序验证
echo "\n--- LRU Order Verification ---\n";
$cache5 = new LRUCache(4);
$cache5->put('a', 1);
$cache5->put('b', 2);
$cache5->put('c', 3);
$cache5->put('d', 4);
$cache5->get('a');
$cache5->get('c');
$cache5->put('e', 5);
echo "Keys: " . implode(' -> ', $cache5->getKeys()) . "\n";
echo "has('b'): " . ($cache5->has('b') ? 'true' : 'false') . " (should be false)\n";

// 大规模
echo "\n--- Large Scale ---\n";
$largeCache = new LRUCache(100);
for ($i = 0; $i < 500; $i++) {
    $largeCache->put("key_$i", "value_$i");
}
echo "Size: " . $largeCache->getSize() . "\n";
echo "Evictions: " . $largeCache->getStats()['evictions'] . "\n";
echo "has('key_0'): " . ($largeCache->has('key_0') ? 'true' : 'false') . "\n";
echo "has('key_499'): " . ($largeCache->has('key_499') ? 'true' : 'false') . "\n";
