<?php
// AOT-CODEGEN-005 P2 同族扫描 L：while 体内「前置无 else 兄弟 if + 后置单语句 if-break」
// 与 foreach 侧 I 同形，仅把外层循环换成 while。
$hits = 0;
while ($hits < 20) {
    $hits++;
    if ($hits === 1) {
        $mark = 7;
    }
    if ($hits > 3) {
        break;
    }
}
echo "L hits=", $hits, " mark=", (isset($mark) ? $mark : -1), "\n";
