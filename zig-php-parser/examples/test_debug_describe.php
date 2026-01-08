<?php
// Debug describeAll
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
        echo "In describeAll, shapes count: ";
        var_dump(count($shapes));
        return array_map(fn($s) => $s->area(), $shapes);
    }
}

$calc = new Calculator();
$shapes = $calc->getShapes();
echo "shapes count: ";
var_dump(count($shapes));

$described = $calc->describeAll($shapes);
echo "described count: ";
var_dump(count($described));

$shapes2 = $calc->getShapes();
echo "shapes2 count: ";
var_dump(count($shapes2));

echo "Done\n";
