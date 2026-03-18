<?php
// 测试64: 数组展开运算符(...)的高级用法 - 关联数组、字符串键、性能
// 测试目的：验证数组展开的各种边界情况

// 基础展开
$arr1 = [1, 2, 3];
$arr2 = [4, 5, 6];
$combined = [...$arr1, ...$arr2];
echo "Combined: " . implode(', ', $combined) . "\n";

// 关联数组展开（PHP 8.1+）
$assoc1 = ['name' => 'Alice', 'age' => 30];
$assoc2 = ['city' => 'Beijing', 'country' => 'China'];
$merged = [...$assoc1, ...$assoc2];
echo "Merged assoc: " . json_encode($merged) . "\n";

// 混合索引和关联
$mixed = [...$arr1, 'key' => 'value', ...$arr2];
echo "Mixed: " . json_encode($mixed) . "\n";

// 展开与字面量混合
$result = [0, ...$arr1, 100, ...$arr2, 999];
echo "With literals: " . implode(', ', $result) . "\n";

// 函数参数中的展开
function sumAll(int ...$numbers): int {
    return array_sum($numbers);
}

$nums = [1, 2, 3, 4, 5];
echo "Sum of spread: " . sumAll(...$nums) . "\n";

// 展开可遍历对象
class NumberCollection implements IteratorAggregate {
    private array $numbers = [];
    
    public function __construct(array $numbers) {
        $this->numbers = $numbers;
    }
    
    public function getIterator(): Traversable {
        return new ArrayIterator($this->numbers);
    }
}

$collection = new NumberCollection([10, 20, 30]);
$fromObject = [...$collection, 40, 50];
echo "From object: " . implode(', ', $fromObject) . "\n";

// 生成器展开
function countTo(int $n): Generator {
    for ($i = 1; $i <= $n; $i++) {
        yield $i;
    }
}

$fromGenerator = [...countTo(5), ...countTo(3)];
echo "From generator: " . implode(', ', $fromGenerator) . "\n";

// 条件展开
$optional = [1, 2, 3];
$condition = true;
$conditional = [0, ...($condition ? $optional : []), 4, 5];
echo "Conditional (true): " . implode(', ', $conditional) . "\n";

$condition = false;
$conditional = [0, ...($condition ? $optional : []), 4, 5];
echo "Conditional (false): " . implode(', ', $conditional) . "\n";

// 同名键覆盖（后面的覆盖前面的）
$first = ['id' => 1, 'name' => 'First'];
$second = ['id' => 2, 'name' => 'Second', 'extra' => 'data'];
$overridden = [...$first, ...$second];
echo "Overridden: " . json_encode($overridden) . "\n";

// 引用数组展开（创建副本）
$original = ['a', 'b', 'c'];
$copy = [...$original];
$copy[0] = 'modified';
echo "Original[0]: {$original[0]}, Copy[0]: {$copy[0]}\n";

// 在函数调用中展开关联数组
function createUser(string $name, int $age, string $city = 'Unknown'): string {
    return "$name, $age, from $city";
}

$userData = ['name' => 'Bob', 'age' => 25, 'city' => 'Shanghai'];
echo "User: " . createUser(...$userData) . "\n";

// 嵌套展开
$nested = [[1, 2], [3, 4], [5, 6]];
$flat = array_merge(...$nested);
echo "Flattened: " . implode(', ', $flat) . "\n";

// 性能测试：大量元素展开
$large = range(1, 1000);
$start = microtime(true);
$spread = [...$large, ...$large];
$time = microtime(true) - $start;
echo "Spread 2000 elements in " . round($time * 1000, 2) . " ms\n";
?>
