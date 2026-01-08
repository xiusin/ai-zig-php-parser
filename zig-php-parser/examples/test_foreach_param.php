<?php
// Test with foreach on parameter
interface Shape {
    public function describe(): string;
    public function area(): float;
}

class Circle implements Shape {
    public $radius;
    public function __construct($r) {
        $this->radius = $r;
    }
    public function describe(): string {
        return "Circle with radius " . $this->radius;
    }
    public function area(): float {
        return 3.14 * $this->radius * $this->radius;
    }
}

function testForeach(array $shapes) {
    foreach ($shapes as $shape) {
        echo "Shape area: " . $shape->area() . "\n";
    }
}

$shapes = [new Circle(5), new Circle(10)];
testForeach($shapes);
echo "Done\n";
