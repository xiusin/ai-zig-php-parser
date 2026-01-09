<?php
class LinkedList {
    private $head = null;

    public function add($value) {
        $node = ["value" => $value, "next" => $this->head];
        $this->head = &$node;
    }

    public function map($callback) {
        $result = new LinkedList();
        $current = &$this->head;
        while ($current !== null) {
            $result->add($callback($current["value"]));
            $current = &$current["next"];
        }
        return $result;
    }

    public function filter($callback) {
        $result = new LinkedList();
        $current = &$this->head;
        while ($current !== null) {
            if ($callback($current["value"])) {
                $result->add($current["value"]);
            }
            $current = &$current["next"];
        }
        return $result;
    }

    public function reduce($callback, $initial) {
        $accumulator = $initial;
        $current = &$this->head;
        while ($current !== null) {
            $accumulator = $callback($accumulator, $current["value"]);
            $current = &$current["next"];
        }
        return $accumulator;
    }

    public function toArray() {
        $result = [];
        $current = &$this->head;
        while ($current !== null) {
            $result[] = $current["value"];
            $current = &$current["next"];
        }
        return array_reverse($result);
    }
}

$list = new LinkedList();
for ($i = 1; $i <= 5; $i++) {
    $list->add($i);
}

$doubled = $list->map(fn($x) => $x * 2);
echo "Doubled: " . implode(", ", $doubled->toArray()) . "\n";

$filtered = $list->filter(fn($x) => $x % 2 == 1);
echo "Odd: " . implode(", ", $filtered->toArray()) . "\n";

$sum = $list->reduce(fn($carry, $item) => $carry + $item, 0);
echo "Sum: $sum\n";
