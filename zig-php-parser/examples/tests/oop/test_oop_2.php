<?php
// 接口和 trait 测试
interface Drawable {
    public function draw();
}

trait Colorable {
    private $color;
    
    public function setColor($color) {
        $this->color = $color;
    }
    
    public function getColor() {
        return $this->color;
    }
}

class Circle implements Drawable {
    use Colorable;
    
    private $radius;
    
    public function __construct($radius) {
        $this->radius = $radius;
    }
    
    public function draw() {
        return "Drawing a circle with radius " . $this->radius;
    }
}

$circle = new Circle(5);
$circle->setColor("red");
echo $circle->draw() . "\n";
echo "Color: " . $circle->getColor() . "\n";
?>