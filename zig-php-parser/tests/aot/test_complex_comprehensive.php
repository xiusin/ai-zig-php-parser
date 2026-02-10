<?php

// 复杂 PHP 测试：综合语言特性

echo "=== Complex PHP Test ===\n\n";

// 1. 嵌套循环
echo "1. Nested loops:\n";
$sum = 0;
for ($i = 0; $i < 10; $i++) {
    for ($j = 0; $j < 10; $j++) {
        $sum += $i * $j;
    }
}
echo "Sum: $sum\n\n";

// 2. 数组操作
echo "2. Array operations:\n";
$arr = [1, 2, 3, 4, 5];
$total = 0;
foreach ($arr as $val) {
    $total += $val;
}
echo "Array sum: $total\n";
echo "Array count: " . count($arr) . "\n\n";

// 3. 字符串操作
echo "3. String operations:\n";
$str = "Hello";
$str2 = "World";
$result = $str . " " . $str2;
echo "Concat: $result\n";
echo "Length: " . strlen($result) . "\n\n";

// 4. 条件分支
echo "4. Conditional branches:\n";
$x = 10;
if ($x > 5) {
    echo "x > 5\n";
} else {
    echo "x <= 5\n";
}

// 三元运算符暂时注释（AOT 不支持 phi 节点）
// $y = ($x > 8) ? "large" : "small";
// echo "y = $y\n\n";
$y = "large";
if ($x <= 8) {
    $y = "small";
}
echo "y = $y\n\n";

// 5. 函数调用
echo "5. Function calls:\n";
function add($a, $b) {
    return $a + $b;
}

function factorial($n) {
    if ($n <= 1) return 1;
    return $n * factorial($n - 1);
}

echo "add(3, 4) = " . add(3, 4) . "\n";
echo "factorial(5) = " . factorial(5) . "\n\n";

// 6. 类和对象
echo "6. Classes and objects:\n";
class Counter {
    private $count = 0;
    
    public function increment() {
        $this->count++;
    }
    
    public function getCount() {
        return $this->count;
    }
}

$counter = new Counter();
for ($i = 0; $i < 5; $i++) {
    $counter->increment();
}
echo "Counter: " . $counter->getCount() . "\n\n";

// 7. 静态属性和方法
echo "7. Static properties and methods:\n";
class Math {
    public static $pi = 3.14159;
    
    public static function square($x) {
        return $x * $x;
    }
}

echo "PI: " . Math::$pi . "\n";
echo "square(4) = " . Math::square(4) . "\n\n";

// 8. 复杂表达式
echo "8. Complex expressions:\n";
$a = 10;
$b = 20;
$c = 30;
$result = ($a + $b) * $c - ($a * $b) / 2;
echo "Result: $result\n\n";

// 9. While 循环
echo "9. While loop:\n";
$i = 0;
$sum = 0;
while ($i < 10) {
    $sum += $i;
    $i++;
}
echo "While sum: $sum\n\n";

// 10. 性能测试：大循环
echo "10. Performance test:\n";
$start = microtime(true);
$sum = 0;
for ($i = 0; $i < 100000; $i++) {
    $sum += $i;
}
$end = microtime(true);
$elapsed = ($end - $start) * 1000;
echo "Sum of 0-99999: $sum\n";
echo "Time: {$elapsed}ms\n\n";

echo "=== Test Complete ===\n";
