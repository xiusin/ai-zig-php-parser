<?php
// Test getShapes after describeAll
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
$shapes = $calc->getShapes();
$described = $calc->describeAll($shapes);

// Now test getShapes again
echo "Direct: ";
foreach ($calc->getShapes() as $shape) {
    echo $shape->area() . " ";
}
echo "\n";

echo "Done\n";

