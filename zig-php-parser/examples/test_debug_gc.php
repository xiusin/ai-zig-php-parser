<?php
// Test with gc_collect_cycles
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
    
    public function describeAll(array $shapes): array {
        return array_map(fn($s) => $s->area(), $shapes);
    }
}

echo "Start\n";
$calc = new Calculator();

$result = $calc->describeAll([new Circle(1)]);
echo "describeAll returned\n";

unset($result);
echo "result unset\n";

// Force garbage collection
if (function_exists('gc_collect_cycles')) {
    gc_collect_cycles();
    echo "gc_collect_cycles called\n";
}

$shapes = $calc->getShapes();
echo "getShapes returned\n";

echo "Done\n";
