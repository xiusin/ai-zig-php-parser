<?php
// AOT-CODEGEN-005 P2 同族扫描 P：while 体内「前置 if 臂含嵌套 foreach + 后置单语句 if-break」
// 与 N 只差内层循环种类（foreach 头标签未被 RC-3 判据覆盖）。
$hits = 0;
$a = [];
while ($hits < 20) {
    $hits++;
    if ($hits === 1) {
        foreach ([1, 2, 3, 4] as $v) {
            $a['p' . $v] = -$v;
        }
    }
    if ($hits > 3) {
        break;
    }
}
echo "P hits=", $hits, " count=", count($a), "\n";
