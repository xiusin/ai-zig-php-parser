<?php
/**
 * 性能优化基准测试
 * 用于验证优化效果
 */

echo "=== Zig-PHP Performance Benchmark ===\n\n";

// 测试1: 整数算术
echo "1. Integer Arithmetic (1M iterations)\n";
$start = microtime(true);
$sum = 0;
for ($i = 0; $i < 1000000; $i++) {
    $sum = $sum + $i;
}
$end = microtime(true);
echo "   Result: $sum\n";
echo "   Time: " . round(($end - $start) * 1000, 2) . " ms\n\n";

// 测试2: 浮点算术
echo "2. Float Arithmetic (1M iterations)\n";
$start = microtime(true);
$sum = 0.0;
for ($i = 0; $i < 1000000; $i++) {
    $sum = $sum + $i * 0.5;
}
$end = microtime(true);
echo "   Result: $sum\n";
echo "   Time: " . round(($end - $start) * 1000, 2) . " ms\n\n";

// 测试3: 字符串连接
echo "3. String Concatenation (100K iterations)\n";
$start = microtime(true);
$str = "";
for ($i = 0; $i < 100000; $i++) {
    $str = $str . "a";
}
$end = microtime(true);
echo "   Length: " . strlen($str) . "\n";
echo "   Time: " . round(($end - $start) * 1000, 2) . " ms\n\n";

// 测试4: 数组操作
echo "4. Array Operations (100K iterations)\n";
$start = microtime(true);
$arr = [];
for ($i = 0; $i < 100000; $i++) {
    $arr[] = $i;
}
$sum = 0;
foreach ($arr as $v) {
    $sum = $sum + $v;
}
$end = microtime(true);
echo "   Sum: $sum\n";
echo "   Time: " . round(($end - $start) * 1000, 2) . " ms\n\n";

// 测试5: 函数调用
echo "5. Function Calls (1M iterations)\n";
function add($a, $b) {
    return $a + $b;
}
$start = microtime(true);
$sum = 0;
for ($i = 0; $i < 1000000; $i++) {
    $sum = add($sum, 1);
}
$end = microtime(true);
echo "   Result: $sum\n";
echo "   Time: " . round(($end - $start) * 1000, 2) . " ms\n\n";

// 测试6: 递归 (Fibonacci)
echo "6. Recursive Fibonacci (n=30)\n";
function fib($n) {
    if ($n <= 1) return $n;
    return fib($n - 1) + fib($n - 2);
}
$start = microtime(true);
$result = fib(30);
$end = microtime(true);
echo "   fib(30) = $result\n";
echo "   Time: " . round(($end - $start) * 1000, 2) . " ms\n\n";

// 测试7: 对象创建
echo "7. Object Creation (100K iterations)\n";
class Point {
    public $x;
    public $y;
    
    public function __construct($x, $y) {
        $this->x = $x;
        $this->y = $y;
    }
    
    public function distance($other) {
        $dx = $this->x - $other->x;
        $dy = $this->y - $other->y;
        return sqrt($dx * $dx + $dy * $dy);
    }
}

$start = microtime(true);
$points = [];
for ($i = 0; $i < 100000; $i++) {
    $points[] = new Point($i, $i * 2);
}
$end = microtime(true);
echo "   Created: " . count($points) . " objects\n";
echo "   Time: " . round(($end - $start) * 1000, 2) . " ms\n\n";

// 测试8: 方法调用
echo "8. Method Calls (100K iterations)\n";
$start = microtime(true);
$origin = new Point(0, 0);
$total = 0.0;
for ($i = 0; $i < 100000; $i++) {
    $total = $total + $points[$i]->distance($origin);
}
$end = microtime(true);
echo "   Total distance: " . round($total, 2) . "\n";
echo "   Time: " . round(($end - $start) * 1000, 2) . " ms\n\n";

// 测试9: 哈希表操作
echo "9. Hash Table Operations (100K iterations)\n";
$start = microtime(true);
$map = [];
for ($i = 0; $i < 100000; $i++) {
    $key = "key_" . $i;
    $map[$key] = $i;
}
$sum = 0;
for ($i = 0; $i < 100000; $i++) {
    $key = "key_" . $i;
    $sum = $sum + $map[$key];
}
$end = microtime(true);
echo "   Sum: $sum\n";
echo "   Time: " . round(($end - $start) * 1000, 2) . " ms\n\n";

// 测试10: 嵌套循环
echo "10. Nested Loops (1000x1000)\n";
$start = microtime(true);
$sum = 0;
for ($i = 0; $i < 1000; $i++) {
    for ($j = 0; $j < 1000; $j++) {
        $sum = $sum + $i + $j;
    }
}
$end = microtime(true);
echo "   Sum: $sum\n";
echo "   Time: " . round(($end - $start) * 1000, 2) . " ms\n\n";

echo "=== Benchmark Complete ===\n";
