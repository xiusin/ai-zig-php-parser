<?php
// 极度混搭: 集合论 + 集合运算 + 泛型约束 + 迭代器 + 数学证明
echo "=== c022: Set Theory + Operations + Iterator + Math Proof ===\n\n";

class MathSet implements Iterator {
    private array $elements = [];
    private int $position = 0;
    private array $keys = [];

    public function __construct(array $elements = []) {
        foreach ($elements as $e) {
            $this->add($e);
        }
    }

    public function add(mixed $element): self {
        $key = $this->hashElement($element);
        if (!isset($this->elements[$key])) {
            $this->elements[$key] = $element;
            $this->keys = array_keys($this->elements);
        }
        return $this;
    }

    public function remove(mixed $element): self {
        $key = $this->hashElement($element);
        unset($this->elements[$key]);
        $this->keys = array_keys($this->elements);
        return $this;
    }

    public function contains(mixed $element): bool {
        return isset($this->elements[$this->hashElement($element)]);
    }

    public function union(MathSet $other): MathSet {
        $result = new MathSet($this->elements);
        foreach ($other as $e) {
            $result->add($e);
        }
        return $result;
    }

    public function intersection(MathSet $other): MathSet {
        $result = new MathSet();
        foreach ($this->elements as $e) {
            if ($other->contains($e)) {
                $result->add($e);
            }
        }
        return $result;
    }

    public function difference(MathSet $other): MathSet {
        $result = new MathSet();
        foreach ($this->elements as $e) {
            if (!$other->contains($e)) {
                $result->add($e);
            }
        }
        return $result;
    }

    public function symmetricDifference(MathSet $other): MathSet {
        return $this->union($other)->difference($this->intersection($other));
    }

    public function isSubsetOf(MathSet $other): bool {
        foreach ($this->elements as $e) {
            if (!$other->contains($e)) return false;
        }
        return true;
    }

    public function isSupersetOf(MathSet $other): bool {
        return $other->isSubsetOf($this);
    }

    public function isEmpty(): bool {
        return empty($this->elements);
    }

    public function size(): int {
        return count($this->elements);
    }

    public function powerSet(): array {
        $elements = array_values($this->elements);
        $n = count($elements);
        $result = [];
        for ($mask = 0; $mask < (1 << $n); $mask++) {
            $subset = new MathSet();
            for ($i = 0; $i < $n; $i++) {
                if ($mask & (1 << $i)) {
                    $subset->add($elements[$i]);
                }
            }
            $result[] = $subset;
        }
        return $result;
    }

    public function cartesianProduct(MathSet $other): array {
        $result = [];
        foreach ($this->elements as $a) {
            foreach ($other as $b) {
                $result[] = [$a, $b];
            }
        }
        return $result;
    }

    public function toArray(): array {
        return array_values($this->elements);
    }

    public function __toString(): string {
        return "{" . implode(", ", array_map(fn($e) => var_export($e, true), $this->elements)) . "}";
    }

    private function hashElement(mixed $element): string {
        if (is_object($element)) {
            return spl_object_id($element) . ':' . get_class($element);
        }
        if (is_array($element)) {
            return json_encode($element);
        }
        return gettype($element) . ':' . (string)$element;
    }

    // Iterator implementation
    public function current(): mixed { return $this->elements[$this->keys[$this->position]] ?? null; }
    public function key(): mixed { return $this->position; }
    public function next(): void { $this->position++; }
    public function rewind(): void { $this->position = 0; }
    public function valid(): bool { return isset($this->keys[$this->position]); }
}

// === 测试 ===

echo "--- Basic Set Operations ---\n";
$A = new MathSet([1, 2, 3, 4, 5]);
$B = new MathSet([3, 4, 5, 6, 7]);

echo "A = $A\n";
echo "B = $B\n";
echo "A ∪ B = " . $A->union($B) . "\n";
echo "A ∩ B = " . $A->intersection($B) . "\n";
echo "A - B = " . $A->difference($B) . "\n";
echo "A ⊕ B = " . $A->symmetricDifference($B) . "\n";

echo "\n--- Subset/Superset ---\n";
$C = new MathSet([2, 3]);
echo "C = $C\n";
echo "C ⊆ A: " . var_export($C->isSubsetOf($A), true) . "\n";
echo "A ⊇ C: " . var_export($A->isSupersetOf($C), true) . "\n";
echo "C ⊆ B: " . var_export($C->isSubsetOf($B), true) . "\n";

echo "\n--- String Sets ---\n";
$fruits = new MathSet(['apple', 'banana', 'cherry']);
$citrus = new MathSet(['orange', 'lemon', 'lime']);
$tropical = new MathSet(['banana', 'mango']);

echo "Fruits ∪ Tropical = " . $fruits->union($tropical) . "\n";
echo "Fuits ∩ Tropical = " . $fruits->intersection($tropical) . "\n";

echo "\n--- Power Set ---\n";
$small = new MathSet(['a', 'b', 'c']);
$ps = $small->powerSet();
echo "P(S) has " . count($ps) . " subsets\n";
foreach ($ps as $i => $s) {
    echo "  [$i] $s\n";
}

echo "\n--- Cartesian Product ---\n";
$X = new MathSet([1, 2]);
$Y = new MathSet(['a', 'b', 'c']);
$cp = $X->cartesianProduct($Y);
echo "|X × Y| = " . count($cp) . "\n";
foreach ($cp as $pair) {
    echo "  (" . $pair[0] . ", " . $pair[1] . ")\n";
}

echo "\n--- Iterator Usage ---\n";
$iterSet = new MathSet([10, 20, 30, 40, 50]);
echo "Iterating: ";
foreach ($iterSet as $val) {
    echo "$val ";
}
echo "\n";

echo "\n--- Math Properties ---\n";
// Commutativity: A ∪ B = B ∪ A
echo "A ∪ B = B ∪ A: " . var_export($A->union($B)->toArray() === $B->union($A)->toArray(), true) . "\n";
// Associativity: (A ∩ B) ∩ C = A ∩ (B ∩ C)
$D = new MathSet([1, 2, 3]);
echo "Associativity: " . var_export(
    $A->intersection($B)->intersection($D)->toArray() === $A->intersection($B->intersection($D))->toArray(),
    true
) . "\n";
// Empty set
$empty = new MathSet();
echo "Empty set size: " . $empty->size() . "\n";
echo "Empty ∪ A = A: " . var_export($empty->union($A)->toArray() === $A->toArray(), true) . "\n";

echo "\n=== c022 Done ===\n";
