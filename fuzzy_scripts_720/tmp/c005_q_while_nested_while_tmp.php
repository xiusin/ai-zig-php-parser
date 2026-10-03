<?php
// AOT-CODEGEN-005 P2 同族扫描 Q：while 体内「前置 if 臂含嵌套 while + 后置单语句 if-break」
// 内层 while 的出口同样复用外层 if 的 merge 块（while_cond_ 头标签未被 RC-3 判据覆盖）。
$hits = 0;
$a = [];
while ($hits < 20) {
    $hits++;
    if ($hits === 1) {
        $j = 0;
        while ($j < 40) {
            $a['q' . $j] = -$j;
            $j++;
        }
    }
    if ($hits > 3) {
        break;
    }
}
echo "Q hits=", $hits, " count=", count($a), "\n";
