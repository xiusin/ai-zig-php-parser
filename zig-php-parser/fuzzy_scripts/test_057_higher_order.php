<?php
// 测试57: 高阶函数组合
$compose = fn(...$fns) => fn($x) => array_reduce(
    array_reverse($fns),
    fn($acc, $fn) => $fn($acc),
    $x
);

$pipe = fn(...$fns) => fn($x) => array_reduce(
    $fns,
    fn($acc, $fn) => $fn($acc),
    $x
);

// 基本函数
$add1 = fn($x) => $x + 1;
$double = fn($x) => $x * 2;
$square = fn($x) => $x ** 2;

// 组合: square(double(add1(x)))
$composed = $compose($square, $double, $add1);
echo "Composed (1+1)*2^2 = " . $composed(1) . "\n";

// 管道: add1 then double then square
$piped = $pipe($add1, $double, $square);
echo "Piped (1+1)*2^2 = " . $piped(1) . "\n";

// 柯里化
$curry = fn($fn) => fn(...$args) => match(count($args)) {
    0 => $fn,
    default => fn(...$rest) => $fn(...$args, ...$rest),
};

$add = fn($a, $b) => $a + $b;
$curriedAdd = $curry($add);
$add5 = $curriedAdd(5);
echo "Curried add: " . $add5(10) . "\n";

// 偏应用
$partial = fn($fn, ...$partialArgs) => fn(...$args) => $fn(...$partialArgs, ...$args);
$multiply = fn($a, $b, $c) => $a * $b * $c;
$multiplyBy2 = $partial($multiply, 2);
echo "Partial multiply: " . $multiplyBy2(3, 4) . "\n";

// memoize
$memoize = fn($fn) => function($x) use ($fn, &$cache) {
    static $cache = [];
    return $cache[$x] ??= $fn($x);
};

$fib = $memoize(fn($n) => $n < 2 ? $n : $fib($n-1) + $fib($n-2));
echo "Fibonacci 30: " . $fib(30) . "\n";
?>
