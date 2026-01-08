<?php
// Test closer to the original polymorphism test
class Shape {
    public function describe() {
        return "Shape";
    }
}

class Circle extends Shape {
    public $radius;
    public function __construct($r) {
        $this->radius = $r;
    }
    public function describe() {
        return "Circle with radius " . $this->radius;
    }
}

class ShapeCalculator {
    public function getShapes() {
        return [new Circle(5), new Circle(10)];
    }
    
    public function describeAll($shapes) {
        return array_map(fn($s) => $s->describe(), $shapes);
    }
}

$calculator = new ShapeCalculator();
echo "Shapes:\n";
foreach ($calculator->describeAll($calculator->getShapes()) as $desc) {
    echo "  {$desc}\n";
}
echo "Done\n";
