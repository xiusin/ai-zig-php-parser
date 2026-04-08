<?php
// 函数基础测试

// 基础函数
function greet($name) {
    return "Hello, $name!";
}
echo greet("World") . "\n";

// 默认参数
function greetWithDefault($name = "Guest") {
    return "Hello, $name!";
}
echo greetWithDefault() . "\n";
echo greetWithDefault("Alice") . "\n";

// 多个默认参数
function configure($host = "localhost", $port = 8080, $ssl = false) {
    return "host=$host, port=$port, ssl=" . ($ssl ? "true" : "false");
}
echo configure() . "\n";
echo configure("example.com") . "\n";
echo configure("example.com", 443, true) . "\n";

// 类型提示
function add(int $a, int $b): int {
    return $a + $b;
}
echo add(3, 4) . "\n";

// 可空类型
function maybeReturn(?string $val): ?string {
    return $val;
}
echo var_export(maybeReturn(null), true) . "\n";
echo maybeReturn("not null") . "\n";

// 可变参数
function sum(...$numbers) {
    return array_sum($numbers);
}
echo sum(1, 2, 3, 4, 5) . "\n";

// 类型声明+可变参数
function sumInts(int ...$nums): int {
    return array_sum($nums);
}
echo sumInts(10, 20, 30) . "\n";

// 引用参数
function increment(&$value) {
    $value++;
}
$num = 5;
increment($num);
echo "after increment: $num\n";

// 引用返回
function &getReference(&$arr, $key) {
    return $arr[$key];
}
$data = ['a' => 1, 'b' => 2];
getReference($data, 'a') = 100;
echo "modified: " . $data['a'] . "\n";

// 函数作为值
$func = function($x) { return $x * 2; };
echo $func(5) . "\n";

// 箭头函数
$square = fn($x) => $x * $x;
echo $square(7) . "\n";

// 箭头函数捕获变量
$multiplier = 3;
$multiply = fn($x) => $x * $multiplier;
echo $multiply(4) . "\n";

// 递归函数
function factorial($n) {
    if ($n <= 1) return 1;
    return $n * factorial($n - 1);
}
echo "5! = " . factorial(5) . "\n";

// 尾递归
function factorialTail($n, $acc = 1) {
    if ($n <= 1) return $acc;
    return factorialTail($n - 1, $n * $acc);
}
echo "6! = " . factorialTail(6) . "\n";

// 嵌套函数
function outer($x) {
    function inner($y) {
        return $y * 2;
    }
    return inner($x) + 1;
}
echo outer(5) . "\n";

// 静态变量
function counter() {
    static $count = 0;
    $count++;
    return $count;
}
echo counter() . "\n";
echo counter() . "\n";
echo counter() . "\n";

// 严格类型
declare(strict_types=1);
function strictAdd(int $a, int $b): int {
    return $a + $b;
}
echo strictAdd(1, 2) . "\n";
