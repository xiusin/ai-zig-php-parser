<?php
// 极度混搭: 哈希表实现 + 开放寻址 + 布隆过滤器 + 一致性哈希
echo "=== f016: Hash Table + Bloom Filter + Consistent Hash ===\n";

class HashTable {
    private array $table;
    private int $size;
    private int $count = 0;

    public function __construct(int $size = 16) {
        $this->size = $size;
        $this->table = array_fill(0, $size, null);
    }

    private function hash(string $key): int {
        $hash = 0;
        for ($i = 0; $i < strlen($key); $i++) {
            $hash = ($hash * 31 + ord($key[$i])) % $this->size;
        }
        return $hash;
    }

    public function set(string $key, mixed $value): void {
        $idx = $this->hash($key);
        $start = $idx;
        while ($this->table[$idx] !== null && $this->table[$idx][0] !== $key) {
            $idx = ($idx + 1) % $this->size;
            if ($idx === $start) throw new RuntimeException("Hash table full");
        }
        if ($this->table[$idx] === null) $this->count++;
        $this->table[$idx] = [$key, $value];
    }

    public function get(string $key): mixed {
        $idx = $this->hash($key);
        $start = $idx;
        while ($this->table[$idx] !== null) {
            if ($this->table[$idx][0] === $key) return $this->table[$idx][1];
            $idx = ($idx + 1) % $this->size;
            if ($idx === $start) break;
        }
        return null;
    }

    public function has(string $key): bool {
        return $this->get($key) !== null;
    }

    public function delete(string $key): bool {
        $idx = $this->hash($key);
        $start = $idx;
        while ($this->table[$idx] !== null) {
            if ($this->table[$idx][0] === $key) {
                $this->table[$idx] = null;
                $this->count--;
                return true;
            }
            $idx = ($idx + 1) % $this->size;
            if ($idx === $start) break;
        }
        return false;
    }

    public function count(): int { return $this->count; }
    public function loadFactor(): float { return $this->count / $this->size; }

    public function keys(): array {
        $keys = [];
        for ($i = 0; $i < $this->size; $i++) {
            if ($this->table[$i] !== null) $keys[] = $this->table[$i][0];
        }
        return $keys;
    }
}

class BloomFilter {
    private array $bits;
    private int $size;
    private int $hashCount;

    public function __construct(int $size = 256, int $hashCount = 3) {
        $this->size = $size;
        $this->hashCount = $hashCount;
        $this->bits = array_fill(0, $size, false);
    }

    private function hashes(string $item): array {
        $result = [];
        for ($i = 0; $i < $this->hashCount; $i++) {
            $hash = 0;
            $salt = "salt$i";
            $combined = $salt . $item;
            for ($j = 0; $j < strlen($combined); $j++) {
                $hash = ($hash * 31 + ord($combined[$j])) % $this->size;
            }
            $result[] = $hash;
        }
        return $result;
    }

    public function add(string $item): void {
        foreach ($this->hashes($item) as $h) {
            $this->bits[$h] = true;
        }
    }

    public function mightContain(string $item): bool {
        foreach ($this->hashes($item) as $h) {
            if (!$this->bits[$h]) return false;
        }
        return true;
    }

    public function countTrue(): int {
        return count(array_filter($this->bits));
    }
}

class ConsistentHash {
    private array $ring = [];
    private int $replicas;

    public function __construct(int $replicas = 3) {
        $this->replicas = $replicas;
    }

    private function hash(string $key): int {
        $hash = 5381;
        for ($i = 0; $i < strlen($key); $i++) {
            $hash = (($hash << 5) + $hash + ord($key[$i])) & 0x7FFFFFFF;
        }
        return $hash;
    }

    public function addNode(string $node): void {
        for ($i = 0; $i < $this->replicas; $i++) {
            $virtualKey = "$node#$i";
            $this->ring[$this->hash($virtualKey)] = $node;
        }
        ksort($this->ring);
    }

    public function removeNode(string $node): void {
        foreach ($this->ring as $hash => $n) {
            if ($n === $node) unset($this->ring[$hash]);
        }
    }

    public function getNode(string $key): ?string {
        if (empty($this->ring)) return null;
        $hash = $this->hash($key);
        foreach ($this->ring as $ringHash => $node) {
            if ($ringHash >= $hash) return $node;
        }
        return reset($this->ring); // 环回
    }

    public function getNodes(): array {
        return array_unique(array_values($this->ring));
    }
}

// === 测试 ===
echo "--- Hash Table ---\n";
$ht = new HashTable(8);
$ht->set('name', 'Alice');
$ht->set('age', 30);
$ht->set('city', 'NYC');
$ht->set('email', 'alice@test.com');

echo "name: " . $ht->get('name') . "\n";
echo "age: " . $ht->get('age') . "\n";
echo "has 'city': " . var_export($ht->has('city'), true) . "\n";
echo "has 'phone': " . var_export($ht->has('phone'), true) . "\n";
echo "count: " . $ht->count() . "\n";
echo "load factor: " . number_format($ht->loadFactor(), 2) . "\n";
echo "keys: " . implode(', ', $ht->keys()) . "\n";

$ht->delete('age');
echo "After delete 'age': count=" . $ht->count() . "\n";
echo "get 'age': " . var_export($ht->get('age'), true) . "\n";

echo "\n--- Bloom Filter ---\n";
$bf = new BloomFilter(64, 3);
$words = ['apple', 'banana', 'cherry', 'date', 'elderberry'];
foreach ($words as $w) $bf->add($w);

foreach ($words as $w) {
    echo "  $w: " . var_export($bf->mightContain($w), true) . "\n";
}
// 测试可能存在的假阳性
$falsy = ['fig', 'grape', 'honeydew'];
foreach ($falsy as $w) {
    echo "  $w: " . var_export($bf->mightContain($w), true) . "\n";
}
echo "True bits: " . $bf->countTrue() . "/64\n";

echo "\n--- Consistent Hash ---\n";
$ch = new ConsistentHash(5);
$ch->addNode('ServerA');
$ch->addNode('ServerB');
$ch->addNode('ServerC');

echo "Nodes: " . implode(', ', $ch->getNodes()) . "\n";

$keys = ['user:1', 'user:2', 'user:3', 'order:1', 'order:2', 'session:1', 'cache:1', 'cache:2'];
$dist = [];
foreach ($keys as $k) {
    $node = $ch->getNode($k);
    echo "  $k → $node\n";
    $dist[$node] = ($dist[$node] ?? 0) + 1;
}
echo "Distribution: " . json_encode($dist) . "\n";

// 移除节点
$ch->removeNode('ServerB');
echo "\nAfter removing ServerB:\n";
foreach ($keys as $k) {
    echo "  $k → " . $ch->getNode($k) . "\n";
}

// 添加节点
$ch->addNode('ServerD');
echo "\nAfter adding ServerD:\n";
$dist2 = [];
foreach ($keys as $k) {
    $node = $ch->getNode($k);
    $dist2[$node] = ($dist2[$node] ?? 0) + 1;
}
echo "Distribution: " . json_encode($dist2) . "\n";

echo "=== f016 Done ===\n";
