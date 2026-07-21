<?php
// 极度混搭: CRDT数据结构 + G-Counter + LWW-Register + OR-Set + 合并
echo "=== f056: CRDT + GCounter + LWW + ORSet ===\n";

class GCounter {
    private array $counts = [];

    public function __construct(private string $nodeId) {}

    public function increment(int $amount = 1): void {
        $this->counts[$this->nodeId] = ($this->counts[$this->nodeId] ?? 0) + $amount;
    }

    public function value(): int {
        return array_sum($this->counts);
    }

    public function merge(GCounter $other): void {
        foreach ($other->counts as $node => $count) {
            if (!isset($this->counts[$node]) || $count > $this->counts[$node]) {
                $this->counts[$node] = $count;
            }
        }
    }

    public function getCounts(): array { return $this->counts; }
}

class PNCounter {
    private GCounter $positive;
    private GCounter $negative;

    public function __construct(string $nodeId) {
        $this->positive = new GCounter($nodeId);
        $this->negative = new GCounter($nodeId);
    }

    public function increment(int $amount = 1): void { $this->positive->increment($amount); }
    public function decrement(int $amount = 1): void { $this->negative->increment($amount); }

    public function value(): int { return $this->positive->value() - $this->negative->value(); }

    public function merge(PNCounter $other): void {
        $this->positive->merge($other->positive);
        $this->negative->merge($other->negative);
    }
}

class LWWRegister {
    private mixed $value = null;
    private int $timestamp = 0;
    private string $nodeId;

    public function __construct(string $nodeId) { $this->nodeId = $nodeId; }

    public function set(mixed $value, int $timestamp): bool {
        if ($timestamp > $this->timestamp) {
            $this->value = $value;
            $this->timestamp = $timestamp;
            return true;
        }
        // Tie-break by nodeId
        if ($timestamp === $this->timestamp && $this->nodeId > $this->nodeId) {
            $this->value = $value;
            return true;
        }
        return false;
    }

    public function get(): mixed { return $this->value; }
    public function getTimestamp(): int { return $this->timestamp; }

    public function merge(LWWRegister $other): void {
        if ($other->timestamp > $this->timestamp) {
            $this->value = $other->value;
            $this->timestamp = $other->timestamp;
        }
    }
}

class ORSet {
    private array $elements = []; // value → set of unique tags
    private array $tombstones = [];
    private string $nodeId;
    private int $counter = 0;

    public function __construct(string $nodeId) { $this->nodeId = $nodeId; }

    public function add(mixed $value): void {
        $tag = $this->nodeId . ':' . (++$this->counter);
        $this->elements[$value][] = $tag;
    }

    public function remove(mixed $value): void {
        if (isset($this->elements[$value])) {
            foreach ($this->elements[$value] as $tag) {
                $this->tombstones[$tag] = true;
            }
            unset($this->elements[$value]);
        }
    }

    public function contains(mixed $value): bool {
        return isset($this->elements[$value]) && !empty($this->elements[$value]);
    }

    public function values(): array {
        return array_keys(array_filter($this->elements, fn($tags) => !empty($tags)));
    }

    public function merge(ORSet $other): void {
        foreach ($other->elements as $value => $tags) {
            foreach ($tags as $tag) {
                if (!isset($this->tombstones[$tag])) {
                    if (!isset($this->elements[$value])) $this->elements[$value] = [];
                    if (!in_array($tag, $this->elements[$value])) {
                        $this->elements[$value][] = $tag;
                    }
                }
            }
        }
        foreach ($other->tombstones as $tag => $v) {
            $this->tombstones[$tag] = true;
            // Remove from elements
            foreach ($this->elements as $value => $tags) {
                $this->elements[$value] = array_values(array_filter($tags, fn($t) => $t !== $tag));
                if (empty($this->elements[$value])) unset($this->elements[$value]);
            }
        }
    }
}

// 测试
echo "--- G-Counter ---\n";
$c1 = new GCounter('nodeA');
$c2 = new GCounter('nodeB');
$c1->increment(3);
$c2->increment(5);
$c1->increment(2);
echo "nodeA: " . $c1->value() . " counts=" . json_encode($c1->getCounts()) . "\n";
echo "nodeB: " . $c2->value() . " counts=" . json_encode($c2->getCounts()) . "\n";
$c1->merge($c2);
echo "After merge: " . $c1->value() . " counts=" . json_encode($c1->getCounts()) . "\n";

echo "\n--- PN-Counter ---\n";
$pn1 = new PNCounter('nodeA');
$pn2 = new PNCounter('nodeB');
$pn1->increment(10);
$pn2->increment(5);
$pn1->decrement(3);
$pn2->decrement(2);
echo "nodeA: " . $pn1->value() . "\n";
echo "nodeB: " . $pn2->value() . "\n";
$pn1->merge($pn2);
echo "After merge: " . $pn1->value() . "\n";

echo "\n--- LWW Register ---\n";
$lww1 = new LWWRegister('nodeA');
$lww2 = new LWWRegister('nodeB');
$lww1->set('old_value', 100);
$lww2->set('new_value', 200);
echo "nodeA: " . $lww1->get() . " (ts={$lww1->getTimestamp()})\n";
echo "nodeB: " . $lww2->get() . " (ts={$lww2->getTimestamp()})\n";
$lww1->merge($lww2);
echo "After merge: " . $lww1->get() . " (ts={$lww1->getTimestamp()})\n";

$lww3 = new LWWRegister('nodeA');
$lww3->set('stale', 50);
$lww3->merge($lww1);
echo "Stale merge: " . $lww3->get() . " (should be new_value)\n";

echo "\n--- OR-Set ---\n";
$s1 = new ORSet('nodeA');
$s2 = new ORSet('nodeB');
$s1->add('apple');
$s1->add('banana');
$s2->add('apple');
$s2->add('cherry');
echo "nodeA: " . json_encode($s1->values()) . "\n";
echo "nodeB: " . json_encode($s2->values()) . "\n";

$s1->remove('apple');
echo "nodeA after remove apple: " . json_encode($s1->values()) . "\n";

$s1->merge($s2);
echo "After merge (nodeA←nodeB): " . json_encode($s1->values()) . "\n";
echo "Contains apple: " . var_export($s1->contains('apple'), true) . "\n";
echo "Contains banana: " . var_export($s1->contains('banana'), true) . "\n";
echo "Contains cherry: " . var_export($s1->contains('cherry'), true) . "\n";

echo "=== f056 Done ===\n";
