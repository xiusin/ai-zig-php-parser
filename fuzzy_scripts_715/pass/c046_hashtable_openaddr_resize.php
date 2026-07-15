<?php
// 极度混搭: 哈希表 + 开放寻址 + 一致性 + 扩容 + 冲突统计 + 持久化
echo "=== c046: HashTable + OpenAddressing + Resize + ConflictStats ===\n\n";

class HashEntry {
    public ?string $key = null;
    public mixed $value = null;
    public bool $deleted = false;

    public function isOccupied(): bool {
        return $this->key !== null && !$this->deleted;
    }
}

class HashTableOA {
    private array $table;
    private int $size;
    private int $count = 0;
    private int $collisions = 0;
    private int $resizes = 0;
    private float $loadFactorThreshold = 0.7;

    public function __construct(int $initialSize = 16) {
        $this->size = $initialSize;
        $this->table = array_fill(0, $initialSize, null);
        for ($i = 0; $i < $initialSize; $i++) {
            $this->table[$i] = new HashEntry();
        }
    }

    public function put(string $key, mixed $value): void {
        if ($this->count / $this->size >= $this->loadFactorThreshold) {
            $this->resize();
        }

        $idx = $this->findSlot($key);
        if ($idx < 0) {
            $this->resize();
            $idx = $this->findSlot($key);
        }

        if (!$this->table[$idx]->isOccupied()) {
            $this->count++;
        }
        $this->table[$idx]->key = $key;
        $this->table[$idx]->value = $value;
        $this->table[$idx]->deleted = false;
    }

    public function get(string $key): mixed {
        $idx = $this->findSlot($key, false);
        if ($idx < 0 || !$this->table[$idx]->isOccupied()) return null;
        return $this->table[$idx]->value;
    }

    public function remove(string $key): bool {
        $idx = $this->findSlot($key, false);
        if ($idx < 0 || !$this->table[$idx]->isOccupied()) return false;
        $this->table[$idx]->deleted = true;
        $this->count--;
        return true;
    }

    public function contains(string $key): bool {
        $idx = $this->findSlot($key, false);
        return $idx >= 0 && $this->table[$idx]->isOccupied();
    }

    private function findSlot(string $key, bool $forInsert = true): int {
        $hash = $this->hash($key);
        $idx = $hash % $this->size;
        $firstDeleted = -1;

        for ($i = 0; $i < $this->size; $i++) {
            $probe = ($idx + $i) % $this->size;
            $entry = $this->table[$probe];

            if ($entry->key === null) {
                return $forInsert ? ($firstDeleted >= 0 ? $firstDeleted : $probe) : -1;
            }

            if ($entry->deleted) {
                if ($firstDeleted < 0) $firstDeleted = $probe;
                continue;
            }

            if ($entry->key === $key) {
                return $probe;
            }

            if ($forInsert) $this->collisions++;
        }

        return $forInsert ? $firstDeleted : -1;
    }

    private function hash(string $key): int {
        $h = 0;
        $len = strlen($key);
        for ($i = 0; $i < $len; $i++) {
            $h = (($h << 5) + $h + ord($key[$i])) & 0x7FFFFFFF;
        }
        return $h;
    }

    private function resize(): void {
        $oldTable = $this->table;
        $oldSize = $this->size;
        $this->size *= 2;
        $this->resizes++;
        $this->table = array_fill(0, $this->size, null);
        for ($i = 0; $i < $this->size; $i++) {
            $this->table[$i] = new HashEntry();
        }
        $this->count = 0;

        foreach ($oldTable as $entry) {
            if ($entry->isOccupied()) {
                $idx = $this->findSlot($entry->key);
                $this->table[$idx]->key = $entry->key;
                $this->table[$idx]->value = $entry->value;
                $this->count++;
            }
        }
    }

    public function getStats(): array {
        return [
            'size' => $this->size,
            'count' => $this->count,
            'load_factor' => round($this->count / $this->size, 3),
            'collisions' => $this->collisions,
            'resizes' => $this->resizes,
        ];
    }

    public function keys(): array {
        $keys = [];
        foreach ($this->table as $entry) {
            if ($entry->isOccupied()) {
                $keys[] = $entry->key;
            }
        }
        return $keys;
    }
}

// === 测试 ===

echo "--- Basic Operations ---\n";
$ht = new HashTableOA(8);

$ht->put('name', 'Alice');
$ht->put('age', 30);
$ht->put('city', 'Beijing');
$ht->put('country', 'China');
$ht->put('email', 'alice@example.com');

echo "name: " . $ht->get('name') . "\n";
echo "age: " . $ht->get('age') . "\n";
echo "city: " . $ht->get('city') . "\n";
echo "email: " . $ht->get('email') . "\n";
echo "nonexistent: " . var_export($ht->get('nonexistent'), true) . "\n";

echo "\nStats: " . json_encode($ht->getStats()) . "\n";
echo "Keys: " . implode(", ", $ht->keys()) . "\n";

echo "\n--- Trigger Resize ---\n";
for ($i = 0; $i < 20; $i++) {
    $ht->put("key_$i", "value_$i");
}
echo "After 25 entries:\n";
echo json_encode($ht->getStats()) . "\n";

echo "\n--- Delete ---\n";
$ht->remove('name');
echo "After remove 'name': " . var_export($ht->get('name'), true) . "\n";
echo "Contains 'name': " . var_export($ht->contains('name'), true) . "\n";
echo "Contains 'age': " . var_export($ht->contains('age'), true) . "\n";

echo "\n--- Large Scale ---\n";
$big = new HashTableOA(16);
$testKeys = [];
for ($i = 0; $i < 100; $i++) {
    $key = "item_" . ($i * 7 + 3);
    $big->put($key, $i * 10);
    $testKeys[] = $key;
}

echo "Stats: " . json_encode($big->getStats()) . "\n";

$found = 0;
foreach ($testKeys as $k) {
    if ($big->get($k) !== null) $found++;
}
echo "Found: $found / " . count($testKeys) . "\n";

echo "\n--- Collision Heavy Keys ---\n";
$collide = new HashTableOA(16);
$similarKeys = [];
for ($i = 0; $i < 20; $i++) {
    $similarKeys[] = "aaa" . chr(65 + $i); // Similar prefix
    $collide->put("aaa" . chr(65 + $i), $i);
}
echo "Stats: " . json_encode($collide->getStats()) . "\n";
foreach ($similarKeys as $k) {
    echo "  $k = " . $collide->get($k) . "\n";
}

echo "\n=== c046 Done ===\n";
