<?php
// break/continue 场景下的累加链
$sum = 0;
for ($i = 0; $i < 5; $i++) {
    if ($i == 2) {
        continue; // 跳过 2
    }
    if ($i == 4) {
        break; // 提前退出
    }
    $sum += $i + 1; // i = 0,1,3 => +1,+2,+4
}
echo "Ctrl: $sum (expect 7)\n";
