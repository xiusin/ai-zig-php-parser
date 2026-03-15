<?php
// 测试12: 可变参数与展开运算符
function sumAll(int ...$numbers): int {
    return array_sum($numbers);
}

function concat(string $separator, string ...$parts): string {
    return implode($separator, $parts);
}

function mixedArgs($required, $optional = "default", ...$rest): array {
    return [$required, $optional, $rest];
}

echo sumAll(1, 2, 3, 4, 5) . "\n";
echo concat("-", "a", "b", "c") . "\n";
print_r(mixedArgs("req", "opt", "extra1", "extra2"));

// 展开运算符调用
$arr = [1, 2, 3, 4, 5];
echo sumAll(...$arr) . "\n";

// 数组合并展开
$arr1 = [1, 2, 3];
$arr2 = [4, 5, 6];
$merged = [...$arr1, ...$arr2];
print_r($merged);

// 关联数组展开
$assoc1 = ['a' => 1, 'b' => 2];
$assoc2 = ['c' => 3, 'd' => 4];
$combined = [...$assoc1, ...$assoc2, 'e' => 5];
print_r($combined);

// 参数解包与可变参数结合
function processItems(callable $processor, ...$items): array {
    return array_map($processor, $items);
}

$result = processItems(fn($x) => $x * 2, ...[1, 2, 3, 4, 5]);
print_r($result);

// 构造函数可变参数
class Container {
    private $items = [];
    
    public function __construct(...$items) {
        $this->items = $items;
    }
    
    public function getItems(): array {
        return $this->items;
    }
}

$container = new Container("a", "b", "c", "d");
print_r($container->getItems());
?>
