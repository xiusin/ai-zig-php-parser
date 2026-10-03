<?php
// AOT-CODEGEN-005 P2 同族扫描 O：for 体内「前置 if 臂含嵌套 for + 后置单语句 if-break」
// 与 foreach 侧 F 同形，仅把外层循环换成 for（RC-2 的 for 侧对应形态）。
$hits = 0;
$a = [];
for ($i = 0; $i < 20; $i++) {
    $hits++;
    if ($hits === 1) {
        for ($j = 0; $j < 40; $j++) {
            $a['g' . $j] = -$j;
        }
    }
    if ($hits > 3) {
        break;
    }
}
echo "O hits=", $hits, " count=", count($a), "\n";
