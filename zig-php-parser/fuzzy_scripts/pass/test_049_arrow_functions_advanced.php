<?php
// 测试49: 箭头函数高级特性 - 自动捕获、嵌套、与闭包对比
// 测试目的：验证fn()语法的自动变量捕获和性能特征

$numbers = range(1, 10);

// 基本箭头函数 vs 传统闭包
$multiplier = 5;
$arrow = array_map(fn($x) => $x * $multiplier, $numbers);
$closure = array_map(function($x) use ($multiplier) { return $x * $multiplier; }, $numbers);
echo "Arrow vs Closure same: " . ($arrow === $closure ? "yes" : "no") . "\n";
echo "Arrow result: " . implode(", ", array_slice($arrow, 0, 5)) . "...\n";

// 箭头函数自动按值捕获（不是引用）
$counter = 10;
$captureTest = array_map(fn($x) => $x + $counter++, $numbers);
// $counter仍然是10，因为箭头函数捕获的是值，不是引用
echo "Counter after arrow: $counter\n";

// 显式引用捕获需要传统闭包
$refCounter = 10;
$refTest = array_map(function($x) use (&$refCounter) { return $x + $refCounter++; }, $numbers);
echo "RefCounter after closure: $refCounter\n";

// 嵌套箭头函数（柯里化）
$outer = 3;
$curried = fn($x) => fn($y) => fn($z) => $x * $y * $z * $outer;
$step1 = $curried(2);
$step2 = $step1(4);
$result = $step2(5);
echo "Curried (2*4*5*3): $result\n";

// 箭头函数在array_filter中的使用
$evens = array_filter($numbers, fn($x) => $x % 2 === 0);
echo "Evens: " . implode(", ", array_values($evens)) . "\n";

// 箭头函数在array_reduce中的使用
$sum = array_reduce($numbers, fn($acc, $x) => $acc + $x, 0);
$product = array_reduce($numbers, fn($acc, $x) => $acc * $x, 1);
echo "Sum: $sum, Product: $product\n";

// 箭头函数与对象
class Calculator {
    public function __construct(private float $base) {}
    public function getMultiplier(): callable {
        return fn($x) => $x * $this->base; // 自动捕获$this
    }
}
$calc = new Calculator(2.5);
$doubleAndHalf = $calc->getMultiplier();
echo "2.5 * 4 = " . $doubleAndHalf(4) . "\n";

// 箭头函数在usort中的使用
$words = ["cherry", "apple", "banana", "date"];
usort($words, fn($a, $b) => strlen($a) <=> strlen($b));
echo "Sorted by length: " . implode(", ", $words) . "\n";

// 箭头函数返回类型推断（PHP 8.0+）
$getType = fn($x): string => gettype($x);
echo "Type of 42: " . $getType(42) . "\n";
echo "Type of 'test': " . $getType("test") . "\n";

// 复杂表达式箭头函数
$complex = array_map(
    fn($x) => $x > 5 ? ($x % 2 == 0 ? $x * 2 : $x * 3) : $x,
    $numbers
);
echo "Complex transform: " . implode(", ", $complex) . "\n";

// 箭头函数解构参数（PHP 7.4+）
$points = [['x' => 1, 'y' => 2], ['x' => 3, 'y' => 4], ['x' => 5, 'y' => 6]];
$distances = array_map(fn($p) => sqrt($p['x']**2 + $p['y']**2), $points);
echo "Distances: " . implode(", ", array_map(fn($d) => round($d, 2), $distances)) . "\n";
?>
