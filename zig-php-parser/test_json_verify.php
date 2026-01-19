<?php
// 测试 JSON 编码和解码功能

echo "=== JSON 编码测试 ===\n";

// 基本类型
echo "null: " . json_encode(null) . "\n";
echo "true: " . json_encode(true) . "\n";
echo "false: " . json_encode(false) . "\n";
echo "integer: " . json_encode(42) . "\n";
echo "float: " . json_encode(3.14) . "\n";
echo "string: " . json_encode("Hello World") . "\n";

// 数组
$arr = [1, 2, 3];
echo "array: " . json_encode($arr) . "\n";

// 对象
$obj = ["name" => "John", "age" => 30];
echo "object: " . json_encode($obj) . "\n";

// 嵌套结构
$nested = [
    "user" => [
        "name" => "Alice",
        "scores" => [90, 85, 95]
    ]
];
echo "nested: " . json_encode($nested) . "\n";

echo "\n=== JSON 解码测试 ===\n";

// 基本类型
var_dump(json_decode("null"));
var_dump(json_decode("true"));
var_dump(json_decode("false"));
var_dump(json_decode("42"));
var_dump(json_decode("3.14"));
var_dump(json_decode('"Hello World"'));

// 数组
$decoded_arr = json_decode('[1, 2, 3]');
var_dump($decoded_arr);

// 对象
$decoded_obj = json_decode('{"name": "John", "age": 30}');
var_dump($decoded_obj);

// 嵌套结构
$decoded_nested = json_decode('{"user": {"name": "Alice", "scores": [90, 85, 95]}}');
var_dump($decoded_nested);

echo "\n=== JSON 往返测试 ===\n";

$original = ["test" => "value", "number" => 123];
$encoded = json_encode($original);
echo "Encoded: $encoded\n";
$decoded = json_decode($encoded);
var_dump($decoded);

echo "\n=== JSON 选项测试 ===\n";

// JSON_PRETTY_PRINT
$data = ["a" => 1, "b" => 2];
echo "Pretty print:\n" . json_encode($data, JSON_PRETTY_PRINT) . "\n";

echo "\n所有测试完成！\n";
?>
