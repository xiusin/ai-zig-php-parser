<?php
// Debug with arrow function returning constant
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
        // Use arrow function returning constant
        return array_map(fn($s) => 42, $shapes);
    }
}

$calc = new Calculator();

// Call describeAll
echo "About to call describeAll\n";
$result = $calc->describeAll([new Circle(1)]);
echo "describeAll done\n";

// Now call getShapes
echo "About to call getShapes\n";
$shapes = $calc->getShapes();
echo "Got shapes\n";

echo "Done\n";
