<?php
// Debug getShapes after describeAll without storing
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

// Call getShapes directly without storing
$described = $calc->describeAll($calc->getShapes());
echo "described: ";
var_dump(count($described));

// Now call getShapes again
$shapes = $calc->getShapes();
echo "shapes: ";
var_dump(count($shapes));

echo "Done\n";
