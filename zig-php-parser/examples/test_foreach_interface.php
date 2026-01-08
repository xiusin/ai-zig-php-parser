<?php
// Test with interface
interface Shape {
    public function describe(): string;
}

class Circle implements Shape {
    public $radius;
    public function __construct($r) {
        $this->radius = $r;
    }
    public function describe(): string {
        return "Circle with radius " . $this->radius;
    }
}

class ShapeCalculator {
    public function getShapes(): array {
        return [new Circle(5), new Circle(10)];
    }
    
    public function describeAll(array $shapes): array {
        return array_map(fn($s) => $s->describe(), $shapes);
    }
}

$calculator = new ShapeCalculator();
echo "Shapes:\n";
foreach ($calculator->describeAll($calculator->getShapes()) as $desc) {
    echo "  {$desc}\n";
}
echo "Done\n";
