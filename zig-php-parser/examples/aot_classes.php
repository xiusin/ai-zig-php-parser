<?php
/**
 * AOT Compilation Example: Classes and OOP
 * 
 * Demonstrates object-oriented programming in AOT-compiled PHP.
 * 
 * Compile with:
 *   zig-php --compile --optimize=release-safe examples/aot_classes.php
 */

// Simple class
class Point {
    public int $x;
    public int $y;
    
    public function __construct(int $x, int $y) {
        $this->x = $x;
        $this->y = $y;
    }
    
    public function distance(Point $other): float {
        $dx = $this->x - $other->x;
        $dy = $this->y - $other->y;
        return sqrt($dx * $dx + $dy * $dy);
    }
    
    public function toString(): string {
        return "(" . $this->x . ", " . $this->y . ")";
    }
}

// Class with inheritance
class Rectangle {
    protected int $width;
    protected int $height;
    
    public function __construct(int $width, int $height) {
        $this->width = $width;
        $this->height = $height;
    }
    
    public function area(): int {
        return $this->width * $this->height;
    }
    
    public function perimeter(): int {
        return 2 * ($this->width + $this->height);
    }
}

class Square extends Rectangle {
    public function __construct(int $side) {
        parent::__construct($side, $side);
    }
}

// Test Point class
$p1 = new Point(0, 0);
$p2 = new Point(3, 4);
echo "Point 1: " . $p1->toString() . "\n";
echo "Point 2: " . $p2->toString() . "\n";
echo "Distance: " . $p1->distance($p2) . "\n";

// Test Rectangle and Square
$rect = new Rectangle(5, 3);
echo "Rectangle area: " . $rect->area() . "\n";
echo "Rectangle perimeter: " . $rect->perimeter() . "\n";

$square = new Square(4);
echo "Square area: " . $square->area() . "\n";
echo "Square perimeter: " . $square->perimeter() . "\n";
