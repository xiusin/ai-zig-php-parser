<?php
// 测试复杂数组操作

// 1. 多维数组
$matrix = [
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9]
];

echo "Matrix[1][2] = " . $matrix[1][2] . "\n";

// 2. 关联数组
$user = [
    "name" => "Alice",
    "age" => 30,
    "email" => "alice@example.com",
    "roles" => ["admin", "user"]
];

echo "User: " . $user["name"] . ", Age: " . $user["age"] . "\n";
echo "Roles: " . implode(", ", $user["roles"]) . "\n";

// 3. 数组解构
[$first, $second, $third] = [10, 20, 30];
echo "First: $first, Second: $second, Third: $third\n";

// 4. 数组合并和展开
$arr1 = [1, 2, 3];
$arr2 = [4, 5, 6];
$merged = [...$arr1, ...$arr2];
echo "Merged: " . implode(", ", $merged) . "\n";

// 5. 数组函数链式调用
$numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

$result = array_filter($numbers, fn($x) => $x % 2 == 0);
$result = array_map(fn($x) => $x * 2, $result);
$sum = array_reduce($result, fn($carry, $x) => $carry + $x, 0);

echo "Sum of doubled evens: $sum\n";

// 6. 数组排序
$data = [
    ["name" => "Bob", "score" => 85],
    ["name" => "Alice", "score" => 92],
    ["name" => "Charlie", "score" => 78]
];

usort($data, function($a, $b) {
    if ($a["score"] > $b["score"]) return -1;
    if ($a["score"] < $b["score"]) return 1;
    return 0;
});

echo "Top scorer: " . $data[0]["name"] . " (" . $data[0]["score"] . ")\n";

// 7. 数组键值操作
$keys = array_keys($user);
$values = array_values($user);
echo "Keys: " . implode(", ", $keys) . "\n";

// 8. 数组切片和拼接
$slice = array_slice($numbers, 2, 4);
echo "Slice [2:4]: " . implode(", ", $slice) . "\n";

// 9. 数组去重
$duplicates = [1, 2, 2, 3, 3, 3, 4, 5, 5];
$unique = array_unique($duplicates);
echo "Unique: " . implode(", ", $unique) . "\n";

// 10. 数组翻转
$flipped = array_flip(["a" => 1, "b" => 2, "c" => 3]);
echo "Flipped keys: " . implode(", ", array_keys($flipped)) . "\n";
