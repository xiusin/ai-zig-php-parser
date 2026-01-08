<?php
// Debug arrow function alone (not in array_map)
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
$circle = new Circle(1);

// Use arrow function
$fn = fn($s) => $s->area();
$result = $fn($circle);
echo "Arrow function result: {$result}\n";

// Now call getShapes
echo "About to call getShapes\n";
$shapes = $calc->getShapes();
echo "Got shapes\n";

echo "Done\n";
