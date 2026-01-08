<?php
// Debug getShapes alone
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
    
    public function describeAll(array $shapes): array {
        return array_map(fn($s) => $s->area(), $shapes);
    }
}

$calc = new Calculator();

// Call describeAll first
$calc->describeAll([new Circle(1)]);

// Now call getShapes
echo "About to call getShapes\n";
$shapes = $calc->getShapes();
echo "Got shapes\n";

echo "Done\n";
