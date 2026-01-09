<?php
// Interface implementation and multiple interfaces
interface Drawable {
    public function draw();
    public function getColor();
}

interface Resizable {
    public function resize($width, $height);
    public function getDimensions();
}

interface Movable {
    public function move($x, $y);
    public function getPosition();
}

// Class implementing multiple interfaces
class Rectangle implements Drawable, Resizable, Movable {
    private $width;
    private $height;
    private $x;
    private $y;
    private $color;
    
    public function __construct($width, $height, $color = "black") {
        $this->width = $width;
        $this->height = $height;
        $this->x = 0;
        $this->y = 0;
        $this->color = $color;
    }
    
    public function draw() {
        return "Drawing rectangle at ({$this->x}, {$this->y}) with size {$this->width}x{$this->height}";
    }
    
    public function getColor() {
        return $this->color;
    }
    
    public function resize($width, $height) {
        $this->width = $width;
        $this->height = $height;
    }
    
    public function getDimensions() {
        return "{$this->width}x{$this->height}";
    }
    
    public function move($x, $y) {
        $this->x = $x;
        $this->y = $y;
    }
    
    public function getPosition() {
        return "({$this->x}, {$this->y})";
    }
}

class Circle implements Drawable, Resizable, Movable {
    private $radius;
    private $x;
    private $y;
    private $color;
    
    public function __construct($radius, $color = "red") {
        $this->radius = $radius;
        $this->x = 0;
        $this->y = 0;
        $this->color = $color;
    }
    
    public function draw() {
        return "Drawing circle at ({$this->x}, {$this->y}) with radius {$this->radius}";
    }
    
    public function getColor() {
        return $this->color;
    }
    
    public function resize($width, $height) {
        $this->radius = min($width, $height) / 2;
    }
    
    public function getDimensions() {
        return "radius: {$this->radius}";
    }
    
    public function move($x, $y) {
        $this->x = $x;
        $this->y = $y;
    }
    
    public function getPosition() {
        return "({$this->x}, {$this->y})";
    }
}

// Test interfaces
$shapes = [
    new Rectangle(100, 50, "blue"),
    new Circle(25, "green"),
];

foreach ($shapes as $shape) {
    echo $shape->draw() . "\n";
    echo $shape->getColor() . "\n";
    echo $shape->getDimensions() . "\n";
    echo $shape->getPosition() . "\n";
    
    $shape->move(10, 20);
    echo "After move: " . $shape->getPosition() . "\n";
    
    $shape->resize(200, 100);
    echo "After resize: " . $shape->getDimensions() . "\n";
    echo "---\n";
}

echo "Done\n";
