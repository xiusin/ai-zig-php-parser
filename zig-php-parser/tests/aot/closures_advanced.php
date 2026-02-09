<?php
// 测试高级闭包特性

// 1. 闭包捕获变量
function createCounter(int $start = 0): callable {
    $count = $start;
    return function() use (&$count): int {
        return ++$count;
    };
}

$counter1 = createCounter(10);
$counter2 = createCounter(100);

echo "Counter1: " . $counter1() . "\n"; // 11
echo "Counter1: " . $counter1() . "\n"; // 12
echo "Counter2: " . $counter2() . "\n"; // 101

// 2. 闭包作为回调
$numbers = [1, 2, 3, 4, 5];
$multiplier = 3;

$result = array_map(function($n) use ($multiplier) {
    return $n * $multiplier;
}, $numbers);

echo "Mapped: " . implode(", ", $result) . "\n";

// 3. 箭头函数
$squared = array_map(fn($x) => $x * $x, $numbers);
echo "Squared: " . implode(", ", $squared) . "\n";

// 4. 闭包绑定到对象
class Calculator {
    private int $base = 10;
    
    public function getAdder(): callable {
        return function(int $x): int {
            return $this->base + $x;
        };
    }
}

$calc = new Calculator();
$adder = $calc->getAdder();
echo "10 + 5 = " . $adder(5) . "\n";

// 5. 嵌套闭包
function outer(string $prefix): callable {
    return function(string $middle) use ($prefix): callable {
        return function(string $suffix) use ($prefix, $middle): string {
            return $prefix . "-" . $middle . "-" . $suffix;
        };
    };
}

$builder = outer("start");
$middle = $builder("middle");
echo "Result: " . $middle("end") . "\n";

// 6. 闭包递归
$factorial = null;
$factorial = function(int $n) use (&$factorial): int {
    if ($n <= 1) return 1;
    return $n * $factorial($n - 1);
};

echo "5! = " . $factorial(5) . "\n";
