<?php
// 永久探针：AOT-CODEGEN-005 RC-4 的 Y6 单形（臂尾 continue + if 之后有兄弟语句 ⇒ if 有独立 merge 块）。
// 与 c005_rc4_break_after_nested_loop_tmp.php 的 Y6 同构，拆成单形便于 --dump-ir / --dump-zig-path 阅读。
// 判据：PHP 真值 visited=5 hit=3 count_x=4（continue 跳过 $hit++ 两轮）。
function mkr6(int $n): array {
    $a = [];
    for ($i = 0; $i < $n; $i++) {
        $a['k' . $i] = $i;
    }
    return $a;
}

$b = mkr6(5);
$x = [];
$w = 0;
$hit = 0;
foreach ($b as $key => $val) {
    $w++;
    if ($w < 3) {
        for ($j = 0; $j < 2; $j++) {
            $x[$w . "_" . $j] = $j;
        }
        continue;
    }
    $hit++;
}
echo "Y6MIN visited={$w} hit={$hit} count_x=" . count($x) . "\n";
