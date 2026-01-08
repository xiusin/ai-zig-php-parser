<?php
// Find exact line that crashes
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
        echo "Line A: getShapes called\n";
        return [new Circle(5), new Circle(10)];
    }
    
    public function describeAll(array $shapes): array {
        echo "Line B: describeAll called\n";
        return array_map(fn($s) => $s->area(), $shapes);
    }
}

echo "Line 1: Start\n";
$calc = new Calculator();
echo "Line 2: Calculator created\n";

echo "Line 3: About to call describeAll\n";
$result = $calc->describeAll([new Circle(1)]);
echo "Line 4: describeAll returned\n";

echo "Line 5: About to call getShapes\n";
$shapes = $calc->getShapes();
echo "Line 6: getShapes returned\n";

echo "Line 7: Done\n";

