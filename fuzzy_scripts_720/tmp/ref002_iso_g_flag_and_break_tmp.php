<?php
// 隔离探针 G：bisect 因子①「嵌套 for 的 if 用 bool 旗标条件（非 ===）+ 后置单语句 if-break」
// 与 B（旗标 + 嵌套 for，无 break）唯一差别是有 break；与 F 唯一差别是条件是 $first 而非 $hits === 1。
$a = [];
for ($i = 0; $i < 20; $i++) {
    $a['k' . $i] = $i;
}
$hits = 0;
$first = true;
foreach ($a as $key => $value) {
    $hits++;
    if ($first) {
        $first = false;
        for ($j = 0; $j < 40; $j++) {
            $a['g' . $j] = -$j;
        }
    }
    if ($hits > 3) {
        break;
    }
}
echo "G hits=", $hits, " count=", count($a), "\n";
