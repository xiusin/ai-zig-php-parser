<?php
// OOP 继承：父类方法、属性继承、方法重写、parent 调用

abstract class Shape {
    protected string $name;

    public function __construct(string $name) {
        $this->name = $name;
    }

    abstract public function area(): float;
    abstract public function perimeter(): float;

    public function describe(): string {
        return sprintf("%s: area=%.2f, perimeter=%.2f", $this->name, $this->area(), $this->perimeter());
    }
}

class Circle extends Shape {
    public function __construct(private float $radius) {
        parent::__construct("Circle");
    }

    public function area(): float {
        return M_PI * $this->radius * $this->radius;
    }

    public function perimeter(): float {
        return 2 * M_PI * $this->radius;
    }
}

class Rectangle extends Shape {
    public function __construct(private float $width, private float $height) {
        parent::__construct("Rectangle");
    }

    public function area(): float {
        return $this->width * $this->height;
    }

    public function perimeter(): float {
        return 2 * ($this->width + $this->height);
    }
}

class Square extends Rectangle {
    public function __construct(float $side) {
        parent::__construct($side, $side);
        $this->name = "Square";
    }
}

class Triangle extends Shape {
    public function __construct(private float $a, private float $b, private float $c) {
        parent::__construct("Triangle");
    }

    public function area(): float {
        $s = $this->perimeter() / 2;
        return sqrt($s * ($s - $this->a) * ($s - $this->b) * ($s - $this->c));
    }

    public function perimeter(): float {
        return $this->a + $this->b + $this->c;
    }
}

// 测试各种形状
$circle = new Circle(5);
echo $circle->describe() . "\n";

$rect = new Rectangle(4, 6);
echo $rect->describe() . "\n";

$square = new Square(4);
echo $square->describe() . "\n";

$triangle = new Triangle(3, 4, 5);
echo $triangle->describe() . "\n";

// 测试多态
$shapes = [$circle, $rect, $square, $triangle];
$totalArea = 0;
foreach ($shapes as $shape) {
    $totalArea += $shape->area();
}
echo "total_area: " . sprintf("%.2f", $totalArea) . "\n";

// 测试 instanceof
echo "is_shape: " . ($circle instanceof Shape ? 'true' : 'false') . "\n";
echo "is_rect: " . ($square instanceof Rectangle ? 'true' : 'false') . "\n";

// 测试继承链中的属性
echo "circle_name: " . $circle->name . "\n";
echo "square_name: " . $square->name . "\n";
