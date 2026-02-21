<?php
// 测试：可变参数函数
function sum_all(...$numbers) {
    $total = 0;
    $i = 0;
    while ($i < count($numbers)) {
        $total += $numbers[$i];
        $i++;
    }
    return $total;
}

function concat_strings(...$strings) {
    $result = "";
    $i = 0;
    while ($i < count($strings)) {
        $result .= $strings[$i];
        $i++;
    }
    return $result;
}

echo "sum_all(1, 2, 3): " . sum_all(1, 2, 3) . "\n";
echo "sum_all(10, 20, 30, 40): " . sum_all(10, 20, 30, 40) . "\n";

echo "concat('Hello', ' ', 'World'): " . concat_strings("Hello", " ", "World") . "\n";

// 默认参数
function greet($name, $greeting = "Hello") {
    return $greeting . ", " . $name . "!";
}

echo greet("Alice") . "\n";
echo greet("Bob", "Hi") . "\n";

// 参数解包
$nums = [5, 10, 15];
echo "sum_all with unpacking: " . sum_all(...$nums) . "\n";
