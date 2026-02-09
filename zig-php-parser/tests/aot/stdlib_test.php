<?php
// 测试常用标准库函数

// 数组函数
$arr = [1, 2, 3, 4, 5];
echo "in_array: " . (in_array(3, $arr) ? "yes" : "no") . "\n";
echo "array_sum: " . array_sum($arr) . "\n";
echo "array_product: " . array_product($arr) . "\n";

// 字符串函数
$str = "Hello World";
echo "str_contains: " . (str_contains($str, "World") ? "yes" : "no") . "\n";
echo "str_starts_with: " . (str_starts_with($str, "Hello") ? "yes" : "no") . "\n";
echo "str_ends_with: " . (str_ends_with($str, "World") ? "yes" : "no") . "\n";

// 数学函数
echo "abs: " . abs(-5) . "\n";
echo "max: " . max(5, 3) . "\n";
echo "min: " . min(5, 3) . "\n";

// 类型函数
echo "is_numeric: " . (is_numeric("123") ? "yes" : "no") . "\n";

// 变量函数
$var = null;
echo "is_null: " . (is_null($var) ? "yes" : "no") . "\n";
echo "isset: " . (isset($var) ? "yes" : "no") . "\n";
echo "empty: " . (empty($var) ? "yes" : "no") . "\n";

// JSON
$data = ["name" => "Alice", "age" => 25];
$json = json_encode($data);
echo "json_encode: $json\n";
$decoded = json_decode($json, true);
echo "json_decode: " . $decoded["name"] . "\n";

echo "All tests passed!\n";
