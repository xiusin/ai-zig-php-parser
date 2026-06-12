<?php
// 回调函数测试

// 基础回调
function applyCallback(callable $callback, $value) {
    return $callback($value);
}

echo "double: " . applyCallback(fn($x) => $x * 2, 5) . "\n";
echo "square: " . applyCallback(fn($x) => $x * $x, 5) . "\n";

// 命名函数回调
function uppercase($str) {
    return strtoupper($str);
}
echo "uppercase: " . applyCallback('uppercase', 'hello') . "\n";

// 静态方法回调
class StaticCallback {
    public static function triple($x) {
        return $x * 3;
    }
}

echo "static method: " . call_user_func(['StaticCallback', 'triple'], 5) . "\n";
echo "static method alt: " . call_user_func('StaticCallback::triple', 5) . "\n";

// 实例方法回调
class InstanceCallback {
    public function add($a, $b) {
        return $a + $b;
    }
}

$inst = new InstanceCallback();
echo "instance method: " . call_user_func([$inst, 'add'], 3, 4) . "\n";

// 闭包回调
$closure = function($x) { return $x + 10; };
echo "closure: " . call_user_func($closure, 5) . "\n";

// 多参数回调
function reduce(array $arr, callable $callback, $initial) {
    $result = $initial;
    foreach ($arr as $value) {
        $result = $callback($result, $value);
    }
    return $result;
}

$sum = reduce([1, 2, 3, 4, 5], fn($a, $b) => $a + $b, 0);
echo "reduce sum: $sum\n";

// 数组函数回调
$nums = [1, 2, 3, 4, 5];
$squared = array_map(fn($x) => $x * $x, $nums);
echo "array_map: " . implode(', ', $squared) . "\n";

$evens = array_filter($nums, fn($x) => $x % 2 === 0);
echo "array_filter: " . implode(', ', $evens) . "\n";

$product = array_reduce($nums, fn($carry, $item) => $carry * $item, 1);
echo "array_reduce: $product\n";

// usort回调
$users = [
    ['name' => 'Alice', 'age' => 30],
    ['name' => 'Bob', 'age' => 25],
    ['name' => 'Charlie', 'age' => 35]
];

usort($users, fn($a, $b) => $a['age'] <=> $b['age']);
echo "sorted by age: " . implode(', ', array_column($users, 'name')) . "\n";

// call_user_func_array
function sumAll(...$nums) {
    return array_sum($nums);
}

echo "sumAll: " . call_user_func_array('sumAll', [1, 2, 3, 4, 5]) . "\n";

// 回调返回回调
function createComparator($key) {
    return function($a, $b) use ($key) {
        return $a[$key] <=> $b[$key];
    };
}

$items = [
    ['id' => 3, 'name' => 'C'],
    ['id' => 1, 'name' => 'A'],
    ['id' => 2, 'name' => 'B']
];

usort($items, createComparator('id'));
echo "sorted by id: " . implode(', ', array_column($items, 'name')) . "\n";

// 闭包use引用
$multiplier = 2;
$multiplierRef = function($x) use (&$multiplier) {
    $multiplier++;
    return $x * $multiplier;
};

echo "multiplier 1: " . $multiplierRef(5) . "\n";
echo "multiplier 2: " . $multiplierRef(5) . "\n";

// is_callable检查
$valid = 'strtoupper';
$invalid = 'nonexistent_function';

echo "is_callable valid: " . var_export(is_callable($valid), true) . "\n";
echo "is_callable invalid: " . var_export(is_callable($invalid), true) . "\n";

// 回调对象(实现了__invoke的类)
class InvokableClass {
    public function __invoke($x) {
        return $x * $x * $x;
    }
}

$cube = new InvokableClass();
echo "invokable: " . $cube(3) . "\n";
echo "is_callable invokable: " . var_export(is_callable($cube), true) . "\n";
