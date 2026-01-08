<?php
// Debug with interface but no describeAll
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

// Just create an array with interface type
$arr = [new Circle(1)];
echo "Array created\n";

// Now call getShapes
echo "About to call getShapes\n";
$shapes = $calc->getShapes();
echo "Got shapes\n";

echo "Done\n";
