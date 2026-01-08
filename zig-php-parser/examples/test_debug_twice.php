<?php
// Debug getShapes twice
interface Shape {
    public function area(): float;
}

class Circle implements Shape {
    public $radius;
    public function __construct($r) {
        $this->radius = $r;
    }
    public function area(): float {
        return 3.14 * $this->radius * $this->radius;
    }
}

class Calculator {
    public function getShapes(): array {
        return [new Circle(5), new Circle(10)];
    }
}

$calc = new Calculator();

// Call getShapes twice
echo "First: ";
$shapes1 = $calc->getShapes();
var_dump(count($shapes1));

echo "Second: ";
$shapes2 = $calc->getShapes();
var_dump(count($shapes2));

echo "Done\n";
