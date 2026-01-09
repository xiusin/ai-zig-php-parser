<?php
// 索引数组测试
$numbers = [1, 2, 3, 4, 5];
echo "Numbers: " . implode(", ", $numbers) . "\n";

// 关联数组测试
$person = [
    "name" => "John Doe",
    "age" => 30,
    "city" => "New York"
];

echo "Person: " . $person["name"] . ", Age: " . $person["age"] . "\n";

// 多维数组测试
$matrix = [
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9]
];

echo "Matrix:\n";
foreach ($matrix as $row) {
    echo implode(" ", $row) . "\n";
}
?>