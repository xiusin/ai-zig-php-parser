<?php
// Test with more methods like the original
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

class ShapeCalculator {
    public function getShapes(): array {
        return [new Circle(5), new Circle(10)];
    }
    
    public function describeAll(array $shapes): array {
        return array_map(fn($s) => $s->describe(), $shapes);
    }
    
    public function calculateTotalArea(array $shapes): float {
        $total = 0;
        foreach ($shapes as $shape) {
            $total += $shape->area();
        }
        return $total;
    }
}

$calculator = new ShapeCalculator();
echo "Shapes:\n";
foreach ($calculator->describeAll($calculator->getShapes()) as $desc) {
    echo "  {$desc}\n";
}
echo "Total area: " . $calculator->calculateTotalArea($calculator->getShapes()) . "\n";
echo "Done\n";
