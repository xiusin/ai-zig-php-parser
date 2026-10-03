<?php
// AOT-CODEGEN-005 P2 同族扫描 M：for 体内「前置无 else 兄弟 if + 后置单语句 if-break」
// 与 foreach 侧 I 同形，仅把外层循环换成 for。
$hits = 0;
$seen = 0;
for ($i = 0; $i < 20; $i++) {
    $hits++;
    if ($hits === 1) {
        $seen = $i;
    }
    if ($hits > 3) {
        break;
    }
}
echo "M hits=", $hits, " seen=", $seen, "\n";
