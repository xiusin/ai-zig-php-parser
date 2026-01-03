<?php

echo "=== 测试关联数组 ===\n";

// 测试简单赋值
$name = "张三";
echo "变量赋值: $name\n";

// 测试数值数组
$arr = [1, 2, 3];
echo "数值数组: ";
print_r($arr);

// 测试foreach
echo "foreach测试:\n";
foreach ($arr as $k => $v) {
    echo "$k => $v\n";
}

echo "\n完成\n";

?>
