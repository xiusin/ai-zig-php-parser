<?php
// Performance benchmark script

echo "=== PHP Interpreter Performance Benchmark ===\n";

// Benchmark 1: Basic arithmetic operations
$start = microtime(true);
$sum = 0;
for ($i = 0; $i < 10000; $i++) {
    $sum += $i * 2;
}
$end = microtime(true);
echo "Arithmetic operations (10k): " . number_format(($end - $start) * 1000, 2) . "ms\n";

// Benchmark 2: String operations
$start = microtime(true);
$str = "";
for ($i = 0; $i < 1000; $i++) {
    $str .= "test" . $i;
}
$end = microtime(true);
echo "String concatenation (1k): " . number_format(($end - $start) * 1000, 2) . "ms\n";

// Benchmark 3: Array operations
$start = microtime(true);
$arr = [];
for ($i = 0; $i < 5000; $i++) {
    $arr[] = $i;
}
$end = microtime(true);
echo "Array append (5k): " . number_format(($end - $start) * 1000, 2) . "ms\n";

// Benchmark 4: Function calls
function testFunction($x) {
    return $x * 2 + 1;
}

$start = microtime(true);
for ($i = 0; $i < 10000; $i++) {
    testFunction($i);
}
$end = microtime(true);
echo "Function calls (10k): " . number_format(($end - $start) * 1000, 2) . "ms\n";

// Benchmark 5: Object creation and method calls
class TestClass {
    private $value;
    
    public function __construct($value) {
        $this->value = $value;
    }
    
    public function getValue() {
        return $this->value;
    }
    
    public function setValue($value) {
        $this->value = $value;
    }
}

$start = microtime(true);
for ($i = 0; $i < 1000; $i++) {
    $obj = new TestClass($i);
    $obj->setValue($i * 2);
    $obj->getValue();
}
$end = microtime(true);
echo "Object operations (1k): " . number_format(($end - $start) * 1000, 2) . "ms\n";

echo "Benchmark completed!\n";
?>