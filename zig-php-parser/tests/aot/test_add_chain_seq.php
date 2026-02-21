<?php
// 顺序循环累加，检查跨循环保持
$sum = 0;
for ($i = 0; $i < 3; $i++) {
    $sum += $i; // 0+1+2 = 3
}
for ($j = 1; $j <= 3; $j++) {
    $sum += $j * 2; // 2+4+6 = 12
}
echo "Seq: $sum (expect 15)\n";
