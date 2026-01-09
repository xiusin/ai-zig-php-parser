<?php
// Abstract classes and abstract methods
abstract class Shape {
    protected $name;
    protected $color;
    
    public function __construct($name, $color = "black") {
        $this->name = $name;
        $this->color = $color;
    }
    
    abstract public function getArea();
    abstract public function getPerimeter();
    
    public function getName() {
        return $this->name;
    }
    
    public function getColor() {
        return $this->color;
    }
    
    public function setColor($color) {
        $this->color = $color;
    }
    
    final public function describe() {
        return "This is a {$this->color} {$this->name}";
    }
}

class Triangle extends Shape {
    private $base;
    private $height;
    private $side1;
    private $side2;
    private $side3;
    
    public function __construct($base, $height, $side1, $side2, $side3, $color = "red") {
        parent::__construct("Triangle", $color);
        $this->base = $base;
        $this->height = $height;
        $this->side1 = $side1;
        $this->side2 = $side2;
        $this->side3 = $side3;
    }
    
    public function getArea() {
        return 0.5 * $this->base * $this->height;
    }
    
    public function getPerimeter() {
        return $this->side1 + $this->side2 + $this->side3;
    }
}

class Square extends Shape {
    private $side;
    
    public function __construct($side, $color = "blue") {
        parent::__construct("Square", $color);
        $this->side = $side;
    }
    
    public function getArea() {
        return $this->side * $this->side;
    }
    
    public function getPerimeter() {
        return 4 * $this->side;
    }
}

class Hexagon extends Shape {
    private $side;
    
    public function __construct($side, $color = "green") {
        parent::__construct("Hexagon", $color);
        $this->side = $side;
    }
    
    public function getArea() {
        return (3 * sqrt(3) * $this->side * $this->side) / 2;
    }
    
    public function getPerimeter() {
        return 6 * $this->side;
    }
}

// Test abstract classes
$shapes = [
    new Triangle(10, 8, 6, 8, 10, "yellow"),
    new Square(5, "purple"),
    new Hexagon(4, "orange"),
];

foreach ($shapes as $shape) {
    echo $shape->describe() . "\n";
    echo "Area: " . $shape->getArea() . "\n";
    echo "Perimeter: " . $shape->getPerimeter() . "\n";
    echo "---\n";
}

echo "Done\n";