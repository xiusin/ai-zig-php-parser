<?php
class LRUCache {
    private array $cache = [];
    private int $capacity;

    public function __construct(int $capacity) {
        $this->capacity = $capacity;
    }

    public function get(string $key): mixed {
        if (!isset($this->cache[$key])) return -1;
        $value = $this->cache[$key];
        unset($this->cache[$key]);
        $this->cache[$key] = $value;
        return $value;
    }

    public function put(string $key, mixed $value): void {
        if (isset($this->cache[$key])) {
            unset($this->cache[$key]);
        } elseif (count($this->cache) >= $this->capacity) {
            array_shift($this->cache);
        }
        $this->cache[$key] = $value;
    }

    public function __toString(): string {
        return implode(',', array_map(
            fn($k, $v) => "$k:$v",
            array_keys($this->cache),
            array_values($this->cache)
        ));
    }
}

$cache = new LRUCache(3);
$cache->put("a", 1);
$cache->put("b", 2);
$cache->put("c", 3);
echo $cache . "\n";
echo $cache->get("a") . "\n";
$cache->put("d", 4);
echo $cache . "\n";
$cache->get("b");
echo $cache . "\n";
echo "OK\n";
