<?php
abstract class Shape {
    abstract public function area();
}

class Circle extends Shape {
    private $radius;

    public function __construct($radius) {
        $this->radius = $radius;
    }

    public function area() {
        return pi() * $this->radius * $this->radius;
    }
}

class Rectangle extends Shape {
    private $width, $height;

    public function __construct($width, $height) {
        $this->width = $width;
        $this->height = $height;
    }

    public function area() {
        return $this->width * $this->height;
    }
}

$shapes = [
    new Circle(5),
    new Rectangle(4, 6),
    new Circle(3),
];

foreach ($shapes as $shape) {
    $type = get_class($shape);
    $area = $shape->area();
    echo "$type area: " . number_format($area, 2) . "\n";
}
