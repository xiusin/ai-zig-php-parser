<?php
// 数组索引参与累加：load/index + add 链
$arr = [1, 2, 3, 4];
$sum = 0;
for ($i = 0; $i < 4; $i++) {
    $sum += $arr[$i]; // 1+2+3+4 = 10
}
echo "ArrIdx: $sum (expect 10)\n";
