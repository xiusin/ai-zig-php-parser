<?php
// 复杂场景测试 4: 引用和指针语义

// 测试 1: 引用参数
function increment(int &$x): void {
    $x++;
}

$a = 5;
increment($a);
echo "After increment: " . $a . "\n";

// 测试 2: 数组引用
function appendValue(array &$arr, $value): void {
    $arr[] = $value;
}

$numbers = [1, 2, 3];
appendValue($numbers, 4);
appendValue($numbers, 5);
echo "Array: " . implode(", ", $numbers) . "\n";

// 测试 3: 对象引用（对象总是引用传递）
class Counter {
    public int $count = 0;
    
    public function increment(): void {
        $this->count++;
    }
}

function incrementCounter(Counter $counter): void {
    $counter->increment();
}

$c = new Counter();
incrementCounter($c);
incrementCounter($c);
echo "Counter: " . $c->count . "\n";

// 测试 4: 引用返回
function &getReference(array &$arr, int $index) {
    return $arr[$index];
}

$data = [10, 20, 30];
$ref = &getReference($data, 1);
$ref = 99;
echo "Modified array: " . implode(", ", $data) . "\n";

echo "\nTest 4 passed!\n";
