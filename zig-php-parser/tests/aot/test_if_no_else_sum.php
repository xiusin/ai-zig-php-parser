<?php
// if 无 else 的循环累加：触发不完整 incoming/分支块更新
$sum = 0;
for ($i = 0; $i < 6; $i++) {
    if ($i % 2 == 0) {
        $sum += $i; // 0 + 2 + 4 = 6
    }
}
echo "IfNoElse: $sum (expect 6)\n";
