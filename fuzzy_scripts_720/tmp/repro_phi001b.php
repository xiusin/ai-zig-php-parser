<?php
// AOT-PHI-001 变体 B：循环内三个顺序 if 修改同一变量 + 带显式 else 的连续 if
$s = "";
for ($i = 0; $i < 4; $i++) {
    if ($i == 0) {
        $s = $s . "zero";
    } else {
        $s = $s . "other";
    }
    if ($i % 2 == 0) {
        $s = $s . "E";
    } else {
        $s = $s . "O";
    }
    if ($i < 3) {
        $s = $s . ".";
    }
}
echo $s . "\n";
// 期望: zeroE.otherO.zeroE.otherO
?>