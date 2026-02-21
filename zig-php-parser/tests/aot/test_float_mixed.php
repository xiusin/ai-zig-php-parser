<?php
// 浮点与整数混合累加
$sum = 0.5;
for ($i = 0; $i < 3; $i++) {
    $sum += $i * 1.5; // 0,1.5,3 => +4.5
}
for ($j = 0; $j < 2; $j++) {
    $sum += 0.25; // +0.5
}
echo "Float: $sum (expect 5.5)\n";
