<?php
// Test combining multiple features
interface Shape {
    public function area(): float;
}

class Circle implements Shape {
    public $radius;
    public function __construct($r) {
        $this->radius = $r;
    }
    public function area(): float {
        return 3.14 * $this->radius * $this->radius;
    }
}

class Calculator {
    public function getShapes(): array {
        return [new Circle(5), new Circle(10)];
    }
    
    public function sumAreas(array $shapes): float {
        $total = 0;
        foreach ($shapes as $shape) {
            $total += $shape->area();
        }
        return $total;
    }
}

$calc = new Calculator();
$shapes = $calc->getShapes();
echo "Total: " . $calc->sumAreas($shapes) . "\n";
echo "Done\n";

