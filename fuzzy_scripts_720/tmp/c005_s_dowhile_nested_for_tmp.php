<?php
// AOT-CODEGEN-005 P2 同族扫描 S：do-while 体内「前置 if 臂含嵌套 for + 后置单语句 if-break」
// do-while 生成器把体整体交范围行走 [body_idx+1, cond_idx)，派发口径与 N 不同，须单独实测。
$hits = 0;
$a = [];
do {
    $hits++;
    if ($hits === 1) {
        for ($j = 0; $j < 40; $j++) {
            $a['s' . $j] = -$j;
        }
    }
    if ($hits > 3) {
        break;
    }
} while ($hits < 20);
echo "S hits=", $hits, " count=", count($a), "\n";
