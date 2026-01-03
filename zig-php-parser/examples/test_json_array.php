<?php
// 测试 JSON 风格的关联数组语法

// 基本 JSON 对象语法
$person = {"name": "John", "age": 30};
echo "Name: " . $person["name"] . "\n";
echo "Age: " . $person["age"] . "\n";

// 嵌套 JSON 对象
$data = {
    "user": {"name": "Alice", "email": "alice@example.com"},
    "settings": {"theme": "dark", "language": "zh"}
};
echo "User name: " . $data["user"]["name"] . "\n";
echo "Theme: " . $data["settings"]["theme"] . "\n";

// 混合使用 JSON 和 PHP 数组语法
$mixed = {"items": [1, 2, 3], "count": 3};
echo "First item: " . $mixed["items"][0] . "\n";
echo "Count: " . $mixed["count"] . "\n";

// 空对象
$empty = {};
echo "Empty object created\n";

// 使用 PHP 风格的 => 在 {} 中
$php_style = {"key" => "value"};
echo "PHP style in braces: " . $php_style["key"] . "\n";

echo "All JSON array tests passed!\n";
