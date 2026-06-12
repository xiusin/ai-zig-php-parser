<?php
// 闭包和匿名函数测试

// 基础闭包
$closure = function($name) {
    return "Hello, $name!";
};
echo $closure("Closure") . "\n";

// 捕获外部变量（需要use）
$message = "Hello";
$greet = function($name) use ($message) {
    return "$message, $name!";
};
echo $greet("World") . "\n";

// 引用捕获
$count = 0;
$increment = function() use (&$count) {
    $count++;
};
$increment();
$increment();
$increment();
echo "count after closure: $count\n";

// 修改捕获的变量
$value = 10;
$modifier = function($add) use (&$value) {
    $value += $add;
};
$modifier(5);
echo "value after modification: $value\n";

// 闭包作为回调
$numbers = [1, 2, 3, 4, 5];
$squared = array_map(function($n) { return $n * $n; }, $numbers);
echo "squared: " . implode(", ", $squared) . "\n";

// 闭包作为过滤器
$evens = array_filter($numbers, fn($n) => $n % 2 === 0);
echo "evens: " . implode(", ", $evens) . "\n";

// 闭包作为累加器
$sum = array_reduce($numbers, function($carry, $item) {
    return $carry + $item;
}, 0);
echo "sum: $sum\n";

// 返回闭包的函数
function createMultiplier($factor) {
    return function($value) use ($factor) {
        return $value * $factor;
    };
}
$double = createMultiplier(2);
$triple = createMultiplier(3);
echo "double(5) = " . $double(5) . "\n";
echo "triple(5) = " . $triple(5) . "\n";

// 闭包工厂
function createCounter() {
    $count = 0;
    return function() use (&$count) {
        $count++;
        return $count;
    };
}
$counter1 = createCounter();
$counter2 = createCounter();
echo "counter1: " . $counter1() . ", " . $counter1() . "\n";
echo "counter2: " . $counter2() . "\n";

// 闭包与$this
class MyClass {
    public $value = 42;

    public function getClosure() {
        return function() {
            return $this->value;
        };
    }
}

$obj = new MyClass();
$closure = $obj->getClosure();
echo "closure with this: " . $closure() . "\n";

// bindTo测试
class Counter {
    private $count = 0;
    public function increment() { $this->count++; }
    public function getCount() { return $this->count; }
}

$getCount = function() { return $this->count; };
$counter = new Counter();
$counter->increment();
$counter->increment();
$binder = $getCount->bindTo($counter, Counter::class);
echo "bound closure: " . $binder() . "\n";

// 闭包数组
$closures = [
    'add' => fn($a, $b) => $a + $b,
    'sub' => fn($a, $b) => $a - $b,
    'mul' => fn($a, $b) => $a * $b,
];
echo "add(3,2) = " . $closures['add'](3, 2) . "\n";
echo "sub(3,2) = " . $closures['sub'](3, 2) . "\n";
echo "mul(3,2) = " . $closures['mul'](3, 2) . "\n";

// 嵌套闭包
$outer = function($x) {
    return function($y) use ($x) {
        return function($z) use ($x, $y) {
            return $x + $y + $z;
        };
    };
};
$nested = $outer(1)(2);
echo "nested(3) = " . $nested(3) . "\n";

// callable类型提示
function execute(callable $func, ...$args) {
    return $func(...$args);
}
echo "execute: " . execute('strlen', 'hello') . "\n";
echo "execute closure: " . execute(fn($x) => $x * 2, 21) . "\n";
