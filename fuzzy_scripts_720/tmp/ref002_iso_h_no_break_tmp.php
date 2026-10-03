<?php
// 隔离探针 H：bisect 因子②「=== 条件 + 嵌套 for，但**没有** break」
// 与 B 唯一差别是条件用 $hits === 1（计数器）而非 $first 旗标；与 F 唯一差别是去掉 break。
// 若 H 正常 ⇒ 嵌套 for 本身不丢，break 是必要因子。
$a = [];
for ($i = 0; $i < 20; $i++) {
    $a['k' . $i] = $i;
}
$hits = 0;
foreach ($a as $key => $value) {
    $hits++;
    if ($hits === 1) {
        for ($j = 0; $j < 40; $j++) {
            $a['g' . $j] = -$j;
        }
    }
}
echo "H hits=", $hits, " count=", count($a), "\n";
