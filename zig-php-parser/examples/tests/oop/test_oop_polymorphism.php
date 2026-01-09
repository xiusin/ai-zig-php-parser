<?php
// Polymorphism testing
interface Shape {
    public function area(): float;
    public function perimeter(): float;
    public function describe(): string;
}

class Circle implements Shape {
    private $radius;
    
    public function __construct($radius) {
        $this->radius = $radius;
    }
    
    public function area(): float {
        return M_PI * $this->radius * $this->radius;
    }
    
    public function perimeter(): float {
        return 2 * M_PI * $this->radius;
    }
    
    public function describe(): string {
        return "Circle with radius {$this->radius}";
    }
}

class Rectangle implements Shape {
    private $width;
    private $height;
    
    public function __construct($width, $height) {
        $this->width = $width;
        $this->height = $height;
    }
    
    public function area(): float {
        return $this->width * $this->height;
    }
    
    public function perimeter(): float {
        return 2 * ($this->width + $this->height);
    }
    
    public function describe(): string {
        return "Rectangle {$this->width}x{$this->height}";
    }
}

class Triangle implements Shape {
    private $base;
    private $height;
    private $side1;
    private $side2;
    
    public function __construct($base, $height, $side1, $side2) {
        $this->base = $base;
        $this->height = $height;
        $this->side1 = $side1;
        $this->side2 = $side2;
    }
    
    public function area(): float {
        return 0.5 * $this->base * $this->height;
    }
    
    public function perimeter(): float {
        return $this->base + $this->side1 + $this->side2;
    }
    
    public function describe(): string {
        return "Triangle with base {$this->base}";
    }
}

class ShapeCalculator {
    public function calculateTotalArea(array $shapes): float {
        $total = 0;
        foreach ($shapes as $shape) {
            $total += $shape->area();
        }
        return $total;
    }
    
    public function calculateTotalPerimeter(array $shapes): float {
        $total = 0;
        foreach ($shapes as $shape) {
            $total += $shape->perimeter();
        }
        return $total;
    }
    
    public function describeAll(array $shapes): array {
        return array_map(fn($s) => $s->describe(), $shapes);
    }
}

// Test polymorphism
echo "=== Polymorphism Testing ===\n";

$shapes = [
    new Circle(5),
    new Rectangle(4, 6),
    new Triangle(3, 4, 5, 5)
];

$calculator = new ShapeCalculator();

echo "Shapes:\n";
foreach ($calculator->describeAll($shapes) as $desc) {
    echo "  {$desc}\n";
}

echo "\nTotal area: " . $calculator->calculateTotalArea($shapes) . "\n";
echo "Total perimeter: " . $calculator->calculateTotalPerimeter($shapes) . "\n";

echo "\nDone\n";
