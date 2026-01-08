<?php
// Debug getShapes
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
        $arr = [new Circle(5), new Circle(10)];
        echo "getShapes returned: ";
        var_dump(count($arr));
        return $arr;
    }
}

$calc = new Calculator();
$shapes = $calc->getShapes();
echo "After getShapes: ";
var_dump(count($shapes));

$calc->getShapes();
echo "After second getShapes: ";
var_dump(count($shapes));

echo "Done\n";
