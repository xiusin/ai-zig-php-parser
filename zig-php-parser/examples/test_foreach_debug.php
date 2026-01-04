<?php

echo "开始测试\n";

$arr = [1, 2, 3];
echo "数组创建成功\n";
echo "数组长度: " . count($arr) . "\n";

echo "开始foreach\n";
foreach ($arr as $v) {
    echo "值: $v\n";
}
echo "foreach结束\n";

?>
