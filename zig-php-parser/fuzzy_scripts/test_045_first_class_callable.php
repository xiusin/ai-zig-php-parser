<?php
// 一等公民可调用测试 (PHP 8.1+)

// 基础函数引用
function greet(string $name): string {
    return "Hello, $name!";
}

$greetFunc = greet(...);
echo $greetFunc('World') . "\n";

// 带多个参数的函数
function add(int $a, int $b): int {
    return $a + $b;
}

$addFunc = add(...);
echo "add: " . $addFunc(3, 4) . "\n";

// 可变参数函数
function sumAll(int ...$numbers): int {
    return array_sum($numbers);
}

$sumFunc = sumAll(...);
echo "sum: " . $sumFunc(1, 2, 3, 4, 5) . "\n";

// 静态方法引用
class Math {
    public static function square(int $n): int {
        return $n * $n;
    }

    public static function power(int $base, int $exp): int {
        return $base ** $exp;
    }
}

$squareFunc = Math::square(...);
echo "square: " . $squareFunc(5) . "\n";

$powerFunc = Math::power(...);
echo "power: " . $powerFunc(2, 8) . "\n";

// 实例方法引用
class Counter {
    private int $count = 0;

    public function increment(): int {
        return ++$this->count;
    }

    public function add(int $n): int {
        $this->count += $n;
        return $this->count;
    }
}

$counter = new Counter();
$incrementFunc = $counter->increment(...);
echo "increment: " . $incrementFunc() . "\n";
echo "increment: " . $incrementFunc() . "\n";

$addFunc = $counter->add(...);
echo "add 5: " . $addFunc(5) . "\n";

// 闭包转换为第一类可调用
$closure = fn($x) => $x * 2;
// 闭包本身就是可调用的
echo "closure: " . $closure(10) . "\n";

// 对象方法引用
class Greeter {
    public function __construct(private string $prefix) {}

    public function greet(string $name): string {
        return $this->prefix . $name;
    }
}

$greeter = new Greeter('Hello, ');
$greetMethod = $greeter->greet(...);
echo "method: " . $greetMethod('Alice') . "\n";

// 数组函数中使用
$numbers = [1, 2, 3, 4, 5];
$squared = array_map(Math::square(...), $numbers);
echo "squared: " . implode(', ', $squared) . "\n";

// 作为回调传递
function apply(array $data, callable $callback): array {
    return array_map($callback, $data);
}

$result = apply($numbers, fn($x) => $x + 1);
echo "applied: " . implode(', ', $result) . "\n";

// 与usort一起使用
class Comparer {
    public function compare($a, $b): int {
        return $a <=> $b;
    }
}

$comparer = new Comparer();
$unsorted = [3, 1, 4, 1, 5, 9, 2, 6];
usort($unsorted, $comparer->compare(...));
echo "sorted: " . implode(', ', $unsorted) . "\n";

// 内置函数引用
$strlenFunc = strlen(...);
echo "strlen: " . $strlenFunc('hello') . "\n";

$strtoupperFunc = strtoupper(...);
echo "strtoupper: " . $strtoupperFunc('hello') . "\n";

// 类型检查
echo "is_callable: " . var_export(is_callable($greetFunc), true) . "\n";

// call_user_func使用
echo "call_user_func: " . call_user_func($greetFunc, 'PHP') . "\n";

echo "First class callable tests completed\n";
