<?php
// 极度混搭: 分布式系统 + CAP理论 + 一致性哈希 + 向量时钟
echo "=== f113: Distributed + ConsistentHash + VectorClock + Quorum ===\n";

class ConsistentHash {
    private array $ring = [];
    private array $nodes = [];
    private int $virtualNodes;

    public function __construct(int $virtualNodes = 150) { $this->virtualNodes = $virtualNodes; }

    public function addNode(string $node): void {
        $this->nodes[] = $node;
        for ($i = 0; $i < $this->virtualNodes; $i++) {
            $hash = $this->hash("$node#$i");
            $this->ring[$hash] = $node;
        }
        ksort($this->ring);
    }

    public function removeNode(string $node): void {
        $this->nodes = array_diff($this->nodes, [$node]);
        for ($i = 0; $i < $this->virtualNodes; $i++) {
            $hash = $this->hash("$node#$i");
            unset($this->ring[$hash]);
        }
    }

    public function getNode(string $key): ?string {
        if (empty($this->ring)) return null;
        $hash = $this->hash($key);
        foreach ($this->ring as $ringHash => $node) {
            if ($ringHash >= $hash) return $node;
        }
        return reset($this->ring); // wrap around
    }

    public function getNodes(string $key, int $count): array {
        if (empty($this->ring)) return [];
        $hash = $this->hash($key);
        $nodes = [];
        $seen = [];
        $keys = array_keys($this->ring);
        $pos = 0;
        foreach ($keys as $i => $ringHash) {
            if ($ringHash >= $hash) { $pos = $i; break; }
            $pos = 0;
        }
        for ($i = 0; $i < count($keys) && count($nodes) < $count; $i++) {
            $idx = ($pos + $i) % count($keys);
            $node = $this->ring[$keys[$idx]];
            if (!isset($seen[$node])) { $nodes[] = $node; $seen[$node] = true; }
        }
        return $nodes;
    }

    private function hash(string $key): int {
        $h = crc32($key);
        return abs($h);
    }

    public function getStats(): array {
        $counts = array_count_values($this->ring);
        return ['nodes' => count($this->nodes), 'virtual_nodes' => count($this->ring), 'distribution' => $counts];
    }
}

class VectorClock {
    private array $clock = [];

    public function __construct(array $initial = []) { $this->clock = $initial; }

    public function increment(string $nodeId): self {
        $this->clock[$nodeId] = ($this->clock[$nodeId] ?? 0) + 1;
        return $this;
    }

    public function merge(VectorClock $other): self {
        $merged = new self();
        foreach ($this->clock as $node => $time) $merged->clock[$node] = $time;
        foreach ($other->clock as $node => $time) {
            $merged->clock[$node] = max($merged->clock[$node] ?? 0, $time);
        }
        return $merged;
    }

    public function compare(VectorClock $other): string {
        $less = false; $greater = false;
        $allNodes = array_unique(array_merge(array_keys($this->clock), array_keys($other->clock)));
        foreach ($allNodes as $node) {
            $t1 = $this->clock[$node] ?? 0;
            $t2 = $other->clock[$node] ?? 0;
            if ($t1 < $t2) $less = true;
            if ($t1 > $t2) $greater = true;
        }
        if ($less && $greater) return 'concurrent';
        if ($less) return 'before';
        if ($greater) return 'after';
        return 'equal';
    }

    public function getClock(): array { return $this->clock; }
    public function __toString(): string { return '{' . implode(', ', array_map(fn($k, $v) => "$k:$v", array_keys($this->clock), $this->clock)) . '}'; }
}

class Quorum {
    public static function requiredReads(int $n, int $w): int { return $n - $w + 1; }
    public static function requiredWrites(int $n, int $r): int { return $n - $r + 1; }

    public static function canSatisfyQuorum(int $n, int $r, int $w): bool {
        return $r + $w > $n; // 强一致性条件
    }

    public static function consistencyLevel(int $n, int $r, int $w): string {
        if ($r + $w > $n) return 'strong';
        if ($r + $w === $n) return 'eventual';
        return 'weak';
    }
}

class DistributedNode {
    public array $data = [];
    public VectorClock $clock;

    public function __construct(public string $id) { $this->clock = new VectorClock(); }

    public function write(string $key, mixed $value): void {
        $this->clock->increment($this->id);
        $this->data[$key] = ['value' => $value, 'clock' => clone $this->clock];
    }

    public function read(string $key): ?array { return $this->data[$key] ?? null; }

    public function syncFrom(DistributedNode $other): array {
        $conflicts = [];
        foreach ($other->data as $key => $entry) {
            if (!isset($this->data[$key])) {
                $this->data[$key] = $entry;
                $this->clock = $this->clock->merge($entry['clock']);
            } else {
                $cmp = $this->data[$key]['clock']->compare($entry['clock']);
                if ($cmp === 'before') {
                    $this->data[$key] = $entry;
                    $this->clock = $this->clock->merge($entry['clock']);
                } elseif ($cmp === 'concurrent') {
                    $conflicts[] = ['key' => $key, 'local' => $this->data[$key]['value'], 'remote' => $entry['value']];
                }
            }
        }
        return $conflicts;
    }
}

// 测试
echo "--- Consistent Hashing ---\n";
$ch = new ConsistentHash(100);
$ch->addNode('node1');
$ch->addNode('node2');
$ch->addNode('node3');

$keys = [];
for ($i = 0; $i < 1000; $i++) $keys[] = "key_$i";

$distribution = [];
foreach ($keys as $key) {
    $node = $ch->getNode($key);
    $distribution[$node] = ($distribution[$node] ?? 0) + 1;
}
echo "Distribution (1000 keys):\n";
foreach ($distribution as $node => $count) {
    $bar = str_repeat('#', (int)($count / 10));
    echo "  $node: $count $bar\n";
}

echo "\nReplicas for 'key_42': " . implode(' → ', $ch->getNodes('key_42', 3)) . "\n";

echo "\n--- Add node4 ---\n";
$moved = 0;
$beforeMap = [];
foreach ($keys as $key) $beforeMap[$key] = $ch->getNode($key);
$ch->addNode('node4');
$afterMap = [];
foreach ($keys as $key) $afterMap[$key] = $ch->getNode($key);
foreach ($keys as $key) if ($beforeMap[$key] !== $afterMap[$key]) $moved++;
echo "Keys moved: $moved / " . count($keys) . " (" . round($moved / count($keys) * 100, 1) . "%)\n";

$distribution2 = [];
foreach ($keys as $key) {
    $node = $ch->getNode($key);
    $distribution2[$node] = ($distribution2[$node] ?? 0) + 1;
}
echo "New distribution:\n";
foreach ($distribution2 as $node => $count) echo "  $node: $count\n";

echo "\n--- Vector Clocks ---\n";
$vc1 = new VectorClock();
$vc1->increment('A')->increment('A');
echo "vc1 = $vc1\n";

$vc2 = new VectorClock();
$vc2->increment('B')->increment('B')->increment('B');
echo "vc2 = $vc2\n";

echo "vc1 vs vc2: " . $vc1->compare($vc2) . "\n";

$vc3 = $vc1->merge($vc2);
echo "merged = $vc3\n";
echo "vc1 vs merged: " . $vc1->compare($vc3) . "\n";
echo "vc2 vs merged: " . $vc2->compare($vc3) . "\n";

$vc4 = new VectorClock(['A' => 3, 'B' => 2]);
$vc5 = new VectorClock(['A' => 2, 'B' => 3]);
echo "\nvc4 = $vc4\nvc5 = $vc5\n";
echo "vc4 vs vc5: " . $vc4->compare($vc5) . "\n";

echo "\n--- Quorum Consistency ---\n";
$configs = [
    [3, 2, 2], [3, 1, 1], [3, 3, 3], [5, 3, 3], [5, 2, 2], [5, 1, 1],
];
foreach ($configs as [$n, $r, $w]) {
    $level = Quorum::consistencyLevel($n, $r, $w);
    echo "  N=$n R=$r W=$w → $level (R+W=" . ($r + $w) . " " . ($r + $w > $n ? ">" : "<=") . " $n)\n";
}

echo "\n--- Distributed Node Sync ---\n";
$nodeA = new DistributedNode('A');
$nodeB = new DistributedNode('B');

$nodeA->write('x', 1);
$nodeA->write('y', 'hello');
echo "Node A: x={$nodeA->read('x')['value']} y={$nodeA->read('y')['value']} clock={$nodeA->clock}\n";

$nodeB->write('z', true);
$nodeB->write('y', 'world');
echo "Node B: z={$nodeB->read('z')['value']} y={$nodeB->read('y')['value']} clock={$nodeB->clock}\n";

echo "\nSync B → A:\n";
$conflicts = $nodeA->syncFrom($nodeB);
echo "Conflicts: " . count($conflicts) . "\n";
foreach ($conflicts as $c) echo "  key={$c['key']} local={$c['local']} remote={$c['remote']}\n";
echo "Node A after sync: clock={$nodeA->clock}\n";
echo "Node A: x={$nodeA->read('x')['value']} y={$nodeA->read('y')['value']} z={$nodeA->read('z')['value']}\n";

echo "=== f113 Done ===\n";
