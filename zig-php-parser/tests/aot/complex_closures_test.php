<?php
// 复杂场景测试 2: 闭包和高阶函数

// 测试 1: 闭包捕获变量
$multiplier = 3;
$multiply = function($x) use ($multiplier) {
    return $x * $multiplier;
};

echo "Multiply 5 by 3: " . $multiply(5) . "\n";

// 测试 2: 返回闭包的函数
function makeAdder(int $n): callable {
    return function($x) use ($n) {
        return $x + $n;
    };
}

$add5 = makeAdder(5);
$add10 = makeAdder(10);

echo "Add 5 to 3: " . $add5(3) . "\n";
echo "Add 10 to 3: " . $add10(3) . "\n";

// 测试 3: 闭包作为参数
function applyTwice(callable $fn, $value) {
    return $fn($fn($value));
}

$double = function($x) { return $x * 2; };
echo "Double twice 3: " . applyTwice($double, 3) . "\n";

// 测试 4: 数组的高阶函数
$numbers = [1, 2, 3, 4, 5];

$squared = array_map(function($x) { return $x * $x; }, $numbers);
echo "Squared: " . implode(", ", $squared) . "\n";

$evens = array_filter($numbers, function($x) { return $x % 2 === 0; });
echo "Evens: " . implode(", ", $evens) . "\n";

$sum = array_reduce($numbers, function($carry, $item) { return $carry + $item; }, 0);
echo "Sum: " . $sum . "\n";

echo "\nTest 2 passed!\n";
