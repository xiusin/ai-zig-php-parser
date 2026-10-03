<?php
// 隔离探针 I：bisect 因子③「两个单语句 if + break，但**没有**嵌套 for」
// 与 F 唯一差别是第一个 if 体改成单条赋值（不含 for）。
// 若 I 正常 ⇒ 嵌套 for（内层循环块）是必要因子；若 I 也丢 ⇒ 与 for 无关，是「连续单语句 if + break」形态本身。
$a = [];
for ($i = 0; $i < 20; $i++) {
    $a['k' . $i] = $i;
}
$hits = 0;
foreach ($a as $key => $value) {
    $hits++;
    if ($hits === 1) {
        $a['z'] = 9;
    }
    if ($hits > 3) {
        break;
    }
}
echo "I hits=", $hits, " count=", count($a), "\n";
