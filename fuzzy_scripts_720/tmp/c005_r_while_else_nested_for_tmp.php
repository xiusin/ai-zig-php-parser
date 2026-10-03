<?php
// AOT-CODEGEN-005 P2 同族扫描 R：while 体内「带 else 臂的 if，else 臂含嵌套 for」+ 后置 if-break
// 用于探测 RC-3 判据是否只覆盖 then 臂（else 臂尾 br→for_cond_ 为另一条派发路径）。
$hits = 0;
$a = [];
while ($hits < 20) {
    $hits++;
    if ($hits === 2) {
        $a['skip'] = 0;
    } else {
        for ($j = 0; $j < 10; $j++) {
            $a['r' . $j] = -$j;
        }
    }
    if ($hits > 3) {
        break;
    }
}
echo "R hits=", $hits, " count=", count($a), "\n";
