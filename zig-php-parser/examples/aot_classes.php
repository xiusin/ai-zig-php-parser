<?php
/**
 * AOT Compilation Example: Classes and OOP
 * 
 * Demonstrates object-oriented programming in AOT-compiled PHP.
 * 
 * Features demonstrated:
 * - Class definition with properties
 * - Constructor (__construct)
 * - Instance methods
 * - Property access with $this
 * - Class inheritance (extends)
 * - Protected properties
 * - Method overriding
 * - Object instantiation with new
 * - Method calls on objects
 * 
 * Note: OOP support in AOT compilation is experimental.
 * Complex OOP features may not be fully supported.
 * 
 * Compile with:
 *   ./zig-out/bin/php-interpreter --compile examples/aot_classes.php
 * 
 * Compile with optimizations:
 *   ./zig-out/bin/php-interpreter --compile --optimize=release-safe examples/aot_classes.php
 * 
 * Run the compiled binary:
 *   ./aot_classes
 * 
 * Expected output:
 *   Point 1: (0, 0)
 *   Point 2: (3, 4)
 *   Distance: 5
 *   Rectangle area: 15
 *   Rectangle perimeter: 16
 *   Square area: 16
 *   Square perimeter: 16
 */

// Simple class with properties and methods
class Point {
    public int $x;
    public int $y;
    
    public function __construct(int $x, int $y) {
        $this->x = $x;
        $this->y = $y;
    }
    
    // Calculate Euclidean distance to another point
    public function distance(Point $other): float {
        $dx = $this->x - $other->x;
        $dy = $this->y - $other->y;
        return sqrt($dx * $dx + $dy * $dy);
    }
    
    // String representation of the point
    public function toString(): string {
        return "(" . $this->x . ", " . $this->y . ")";
    }
}

// Base class for shapes
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

// Derived class demonstrating inheritance
class Square extends Rectangle {
    public function __construct(int $side) {
        // Call parent constructor with same value for width and height
        parent::__construct($side, $side);
    }
}

// Test Point class
$p1 = new Point(0, 0);
$p2 = new Point(3, 4);
echo "Point 1: " . $p1->toString() . "\n";
echo "Point 2: " . $p2->toString() . "\n";
echo "Distance: " . $p1->distance($p2) . "\n";

// Test Rectangle class
$rect = new Rectangle(5, 3);
echo "Rectangle area: " . $rect->area() . "\n";
echo "Rectangle perimeter: " . $rect->perimeter() . "\n";

// Test Square class (inheritance)
$square = new Square(4);
echo "Square area: " . $square->area() . "\n";
echo "Square perimeter: " . $square->perimeter() . "\n";
