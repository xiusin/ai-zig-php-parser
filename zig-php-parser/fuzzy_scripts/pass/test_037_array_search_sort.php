<?php
// 测试37: 数组搜索与高级排序
$fruits = ["apple", "banana", "cherry", "date", "elderberry"];

// 搜索
$pos = array_search("cherry", $fruits);
echo "Position of 'cherry': $pos\n";

$exists = in_array("banana", $fruits);
echo "'banana' exists: " . ($exists ? "yes" : "no") . "\n";

// 键搜索
$assoc = ["id" => 1, "name" => "test", "status" => "active"];
$hasKey = array_key_exists("name", $assoc);
echo "Key 'name' exists: " . ($hasKey ? "yes" : "no") . "\n";

// 排序
$numbers = [5, 2, 8, 1, 9, 3];
sort($numbers);
echo "Sorted: " . implode(", ", $numbers) . "\n";

rsort($numbers);
echo "Reverse sorted: " . implode(", ", $numbers) . "\n";

// 关联数组排序
$ages = ["Alice" => 30, "Bob" => 25, "Charlie" => 35];
asort($ages);
echo "Age sorted by value: ";
print_r($ages);

ksort($ages);
echo "Age sorted by key: ";
print_r($ages);

// 自定义排序
$words = ["apple", "pie", "strawberry", "kiwi"];
usort($words, function($a, $b) {
    return strlen($a) <=> strlen($b);
});
echo "Sorted by length: " . implode(", ", $words) . "\n";

// 多维排序
$users = [
    ["name" => "Alice", "age" => 30],
    ["name" => "Bob", "age" => 25],
    ["name" => "Charlie", "age" => 35],
];

array_multisort(array_column($users, 'age'), SORT_ASC, $users);
echo "Users sorted by age:\n";
print_r($users);

// 自然排序
$files = ["file1.txt", "file10.txt", "file2.txt"];
natsort($files);
echo "Natural sorted: " . implode(", ", $files) . "\n";
?>
