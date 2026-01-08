<?php
// Debug before and after
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

// Call getShapes before
echo "Before: ";
$shapes1 = $calc->getShapes();
var_dump(count($shapes1));

// Call describeAll
echo "About to call describeAll\n";
$result = $calc->describeAll([new Circle(1)]);
echo "describeAll done, result count: ";
var_dump(count($result));

// Call getShapes after
echo "After: ";
$shapes2 = $calc->getShapes();
var_dump(count($shapes2));

echo "Done\n";

