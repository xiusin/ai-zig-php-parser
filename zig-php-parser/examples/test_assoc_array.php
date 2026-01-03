<?php

echo "=== 测试关联数组 ===\n";

// 测试1: 简单关联数组
$map = ["name" => "张三", "age" => 25];
echo "创建成功\n";
print_r($map);

echo "\n测试2: foreach遍历\n";
foreach ($map as $key => $value) {
    echo "$key => $value\n";
}

echo "\n完成\n";

?>
