<?php
// 简单性能基准测试

// 测试1: 循环求和
$sum = 0;
$i = 0;
while ($i < 1000) {
    $sum = $sum + $i;
    $i = $i + 1;
}
echo $sum;
