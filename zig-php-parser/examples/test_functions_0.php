<?php
// 普通函数测试
function greet($name) {
    return "Hello, " . $name;
}

echo greet("World") . "\n";

// 可变参数函数测试
function sum(...$numbers) {
    return array_sum($numbers);
}

echo "Sum: " . sum(1, 2, 3, 4, 5) . "\n";

// 默认参数测试
function create_user($name, $age = 18) {
    return ["name" => $name, "age" => $age];
}

$user = create_user("Alice");
print_r($user);
?>