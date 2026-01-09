<?php
// OOP高级测试 - 静态成员、接口

class Config {
    private static int $instanceCount = 0;
    private static array $settings = [];
    
    public function __construct() {
        self::$instanceCount = self::$instanceCount + 1;
    }
    
    public static function getInstanceCount(): int {
        return self::$instanceCount;
    }
    
    public static function setSetting(string $key, mixed $value): void {
        self::$settings[$key] = $value;
    }
    
    public static function getSetting(string $key): mixed {
        return self::$settings[$key] ?? null;
    }
}

interface Shape {
    public function getArea(): float;
    public function getPerimeter(): float;
}

class Rectangle implements Shape {
    private float $width;
    private float $height;
    
    public function __construct(float $width, float $height) {
        $this->width = $width;
        $this->height = $height;
    }
    
    public function getArea(): float {
        return $this->width * $this->height;
    }
    
    public function getPerimeter(): float {
        return 2 * ($this->width + $this->height);
    }
    
    public function getDimensions(): string {
        return $this->width . "x" . $this->height;
    }
}

class Circle implements Shape {
    private float $radius;
    
    public function __construct(float $radius) {
        $this->radius = $radius;
    }
    
    public function getArea(): float {
        return 3.14159 * $this->radius * $this->radius;
    }
    
    public function getPerimeter(): float {
        return 2 * 3.14159 * $this->radius;
    }
}

class ShapeCalculator {
    public static function calculateTotalArea(array $shapes): float {
        $total = 0.0;
        foreach ($shapes as $shape) {
            $total = $total + $shape->getArea();
        }
        return $total;
    }
    
    public static function describe(Shape $shape): string {
        return "Shape with area: " . $shape->getArea();
    }
}

// 测试
echo "=== 静态成员 ===\n";
Config::setSetting("debug", true);
Config::setSetting("timeout", 30);
echo "Settings - debug: " . Config::getSetting("debug") . 
     ", timeout: " . Config::getSetting("timeout") . "\n";
echo "Instance count: " . Config::getInstanceCount() . "\n";

$config1 = new Config();
$config2 = new Config();
echo "After 2 instances: " . Config::getInstanceCount() . "\n";

echo "=== 接口和多态 ===\n";
$rect = new Rectangle(5, 3);
$circle = new Circle(4);

echo "Rectangle: " . $rect->getDimensions() . 
     ", Area: " . $rect->getArea() . 
     ", Perimeter: " . $rect->getPerimeter() . "\n";
echo "Circle: Area: " . $circle->getArea() . 
     ", Perimeter: " . $circle->getPerimeter() . "\n";

echo "=== 静态方法调用 ===\n";
$shapes = [$rect, $circle, new Rectangle(2, 2)];
$totalArea = ShapeCalculator::calculateTotalArea($shapes);
echo "Total area: " . $totalArea . "\n";
echo ShapeCalculator::describe($rect) . "\n";
echo ShapeCalculator::describe($circle) . "\n";

echo "=== 完成 ===\n";
?>
