<?php
// 极度混搭: CRDT数据结构 + G-Counter + PN-Counter + LWW-Register + OR-Set
echo "=== c047: CRDT + GCounter + PNCounter + LWW + ORSet ===\n\n";

class GCounter {
    private string $nodeId;
    private array $counts = [];

    public function __construct(string $nodeId) {
        $this->nodeId = $nodeId;
        $this->counts[$nodeId] = 0;
    }

    public function increment(int $amount = 1): void {
        $this->counts[$this->nodeId] += $amount;
    }

    public function value(): int {
        return array_sum($this->counts);
    }

    public function merge(GCounter $other): GCounter {
        $merged = new GCounter($this->nodeId);
        $merged->counts = $this->counts;
        foreach ($other->counts as $node => $count) {
            $merged->counts[$node] = max($merged->counts[$node] ?? 0, $count);
        }
        return $merged;
    }

    public function getState(): array {
        return $this->counts;
    }
}

class PNCounter {
    private GCounter $positive;
    private GCounter $negative;

    public function __construct(string $nodeId) {
        $this->positive = new GCounter($nodeId);
        $this->negative = new GCounter($nodeId);
    }

    public function increment(int $amount = 1): void {
        $this->positive->increment($amount);
    }

    public function decrement(int $amount = 1): void {
        $this->negative->increment($amount);
    }

    public function value(): int {
        return $this->positive->value() - $this->negative->value();
    }

    public function merge(PNCounter $other): PNCounter {
        $result = new PNCounter($this->positive->getState() ? 'node' : 'node');
        $result->positive = $this->positive->merge($other->positive);
        $result->negative = $this->negative->merge($other->negative);
        return $result;
    }
}

class LWWRegister {
    private mixed $value = null;
    private int $timestamp = 0;
    private string $nodeId;

    public function __construct(string $nodeId) {
        $this->nodeId = $nodeId;
    }

    public function set(mixed $value, int $timestamp): void {
        if ($timestamp >= $this->timestamp) {
            $this->value = $value;
            $this->timestamp = $timestamp;
        }
    }

    public function get(): mixed {
        return $this->value;
    }

    public function getTimestamp(): int {
        return $this->timestamp;
    }

    public function merge(LWWRegister $other): LWWRegister {
        $result = new LWWRegister($this->nodeId);
        if ($this->timestamp >= $other->timestamp) {
            $result->value = $this->value;
            $result->timestamp = $this->timestamp;
        } else {
            $result->value = $other->value;
            $result->timestamp = $other->timestamp;
        }
        return $result;
    }
}

class ORSet {
    private string $nodeId;
    private array $elements = [];
    private array $tombstones = [];
    private int $counter = 0;

    public function __construct(string $nodeId) {
        $this->nodeId = $nodeId;
    }

    public function add(mixed $value): void {
        $tag = $this->nodeId . ':' . $this->counter++;
        $key = $this->hashValue($value);
        if (!isset($this->elements[$key])) {
            $this->elements[$key] = ['value' => $value, 'tags' => []];
        }
        $this->elements[$key]['tags'][] = $tag;
    }

    public function remove(mixed $value): void {
        $key = $this->hashValue($value);
        if (isset($this->elements[$key])) {
            if (!isset($this->tombstones[$key])) {
                $this->tombstones[$key] = [];
            }
            $this->tombstones[$key] = array_merge($this->tombstones[$key], $this->elements[$key]['tags']);
            $this->elements[$key]['tags'] = [];
        }
    }

    public function contains(mixed $value): bool {
        $key = $this->hashValue($value);
        return isset($this->elements[$key]) && !empty($this->elements[$key]['tags']);
    }

    public function merge(ORSet $other): ORSet {
        $result = new ORSet($this->nodeId);
        $result->elements = $this->elements;
        $result->tombstones = $this->tombstones;
        $result->counter = $this->counter;

        foreach ($other->elements as $key => $entry) {
            if (!isset($result->elements[$key])) {
                $result->elements[$key] = $entry;
            } else {
                $result->elements[$key]['tags'] = array_unique(array_merge(
                    $result->elements[$key]['tags'],
                    $entry['tags']
                ));
            }
        }

        foreach ($other->tombstones as $key => $tags) {
            if (!isset($result->tombstones[$key])) {
                $result->tombstones[$key] = [];
            }
            $result->tombstones[$key] = array_unique(array_merge(
                $result->tombstones[$key],
                $tags
            ));
        }

        // Remove tombstoned tags
        foreach ($result->elements as $key => &$entry) {
            if (isset($result->tombstones[$key])) {
                $entry['tags'] = array_values(array_diff($entry['tags'], $result->tombstones[$key]));
            }
        }

        return $result;
    }

    public function getValues(): array {
        $values = [];
        foreach ($this->elements as $entry) {
            if (!empty($entry['tags'])) {
                $values[] = $entry['value'];
            }
        }
        return $values;
    }

    private function hashValue(mixed $value): string {
        if (is_string($value)) return $value;
        return json_encode($value);
    }
}

// === 测试 ===

echo "--- G-Counter (Distributed Counter) ---\n";
$counter1 = new GCounter('node1');
$counter2 = new GCounter('node2');
$counter3 = new GCounter('node3');

$counter1->increment(5);
$counter1->increment(3);
$counter2->increment(4);
$counter2->increment(2);
$counter3->increment(7);

echo "Node1: " . $counter1->value() . "\n";
echo "Node2: " . $counter2->value() . "\n";
echo "Node3: " . $counter3->value() . "\n";

$merged = $counter1->merge($counter2)->merge($counter3);
echo "Merged: " . $merged->value() . "\n";
echo "State: " . json_encode($merged->getState()) . "\n";

echo "\n--- PN-Counter (Positive/Negative) ---\n";
$pn1 = new PNCounter('node1');
$pn2 = new PNCounter('node2');

$pn1->increment(10);
$pn1->increment(5);
$pn1->decrement(3);
$pn2->increment(8);
$pn2->decrement(2);
$pn2->decrement(1);

echo "PN1: " . $pn1->value() . "\n";
echo "PN2: " . $pn2->value() . "\n";
$pnMerged = $pn1->merge($pn2);
echo "Merged: " . $pnMerged->value() . "\n";

echo "\n--- LWW-Register (Last-Write-Wins) ---\n";
$lww1 = new LWWRegister('node1');
$lww2 = new LWWRegister('node2');

$lww1->set('version1', 1);
$lww2->set('version2', 2);
$lww1->set('version1b', 3);

echo "LWW1: " . $lww1->get() . " (ts=" . $lww1->getTimestamp() . ")\n";
echo "LWW2: " . $lww2->get() . " (ts=" . $lww2->getTimestamp() . ")\n";

$mergedLWW = $lww1->merge($lww2);
echo "Merged: " . $mergedLWW->get() . " (ts=" . $mergedLWW->getTimestamp() . ")\n";

echo "\n--- OR-Set (Observed-Remove Set) ---\n";
$set1 = new ORSet('node1');
$set2 = new ORSet('node2');

$set1->add('apple');
$set1->add('banana');
$set2->add('apple');
$set2->add('cherry');

echo "Set1: " . implode(", ", $set1->getValues()) . "\n";
echo "Set2: " . implode(", ", $set2->getValues()) . "\n";
echo "Set1 contains apple: " . var_export($set1->contains('apple'), true) . "\n";

$set1->remove('apple');
echo "After remove apple from Set1: " . implode(", ", $set1->getValues()) . "\n";

$mergedSet = $set1->merge($set2);
echo "Merged: " . implode(", ", $mergedSet->getValues()) . "\n";
echo "Merged contains apple: " . var_export($mergedSet->contains('apple'), true) . "\n";

echo "\n--- Concurrent Operations ---\n";
$a = new GCounter('A');
$b = new GCounter('B');

$a->increment(100);
$b->increment(200);
$aSync = $a->merge($b);
$a->increment(50);
$b->increment(50);

$aFinal = $a->merge($b);
$bFinal = $b->merge($a);
echo "A's view: " . $aFinal->value() . "\n";
echo "B's view: " . $bFinal->value() . "\n";
echo "Converged: " . var_export($aFinal->value() === $bFinal->value(), true) . "\n";

echo "\n=== c047 Done ===\n";
