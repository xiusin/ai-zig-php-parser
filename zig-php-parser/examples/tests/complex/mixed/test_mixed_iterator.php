<?php
class Range implements Iterator {
    private $start;
    private $end;
    private $current;

    public function __construct($start, $end) {
        $this->start = $start;
        $this->end = $end;
        $this->current = $start;
    }

    public function rewind() {
        $this->current = $this->start;
    }

    public function current() {
        return $this->current;
    }

    public function key() {
        return $this->current;
    }

    public function next() {
        $this->current++;
    }

    public function valid() {
        return $this->current <= $this->end;
    }
}

class Composite implements IteratorAggregate {
    private $items = [];

    public function add($item) {
        $this->items[] = $item;
    }

    public function getIterator() {
        return new ArrayIterator($this->items);
    }
}

echo "Range iterator:\n";
foreach (new Range(1, 5) as $num) {
    echo "$num ";
}
echo "\n";

$composite = new Composite();
$composite->add("A");
$composite->add("B");
$composite->add("C");

echo "Composite iterator:\n";
foreach ($composite as $item) {
    echo "$item ";
}
echo "\n";
