<?php
// 测试：单个引用循环 + 复杂表达式
$data = [5, 10, 15, 20, 25];

echo "Original values:\n";
$i = 0;
while ($i < count($data)) {
    echo $data[$i] . " ";
    $i++;
}
echo "\n";

// 使用引用修改
foreach ($data as &$val) {
    $val = $val * 3 + 10;
}

echo "After transformation (val * 3 + 10):\n";
$i = 0;
while ($i < count($data)) {
    echo $data[$i] . " ";
    $i++;
}
echo "\n";

// 计算总和
$sum = 0;
$i = 0;
while ($i < count($data)) {
    $sum += $data[$i];
    $i++;
}
echo "Sum: $sum\n";
