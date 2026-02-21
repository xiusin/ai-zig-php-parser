<?php
// 顺序循环：for 后接 while，验证跨循环累加与 exit/merge 结构
$sum = 0;
for ($i = 0; $i < 3; $i++) {
    $sum += $i + 1; // 1+2+3=6
}

$j = 0;
while ($j < 2) {
    $sum += 10; // +20
    $j++;
}

echo "ForWhile: $sum (expect 26)\n";
