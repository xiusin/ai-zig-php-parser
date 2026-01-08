<?php
// Test with method that takes array parameter
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
    public function sumAreas(array $shapes): float {
        $total = 0;
        foreach ($shapes as $shape) {
            $total += $shape->area();
        }
        return $total;
    }
}

$calc = new Calculator();
$shapes = [new Circle(5), new Circle(10)];
echo "Total: " . $calc->sumAreas($shapes) . "\n";
echo "Done\n";

