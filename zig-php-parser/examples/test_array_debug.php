<?php

echo "=== 测试关联数组 ===\n";

// 测试1: 简单关联数组
$map = ["name" => "张三", "age" => 25];
echo "数组内容: ";
print_r($map);
echo "\n";

// 测试2: foreach遍历
echo "foreach遍历:\n";
foreach ($map as $key => $value) {
    echo "  $key => $value\n";
}

// 测试3: 直接访问
echo "直接访问:\n";
echo "  name: " . $map["name"] . "\n";
echo "  age: " . $map["age"] . "\n";

// 测试4: 数值索引数组
$arr = [1, 2, 3];
echo "\n数值数组: ";
print_r($arr);
echo "\n";

echo "foreach数值数组:\n";
foreach ($arr as $k => $v) {
    echo "  $k => $v\n";
}

?>
