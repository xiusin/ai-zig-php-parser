<?php
// 永久取证探针：AOT-CODEGEN-005 RC-5 facet-1 已闭环形（F-B = Y6MIN）单形隔离，作 facet-2 取证的正控制。
// 从 c005_rc5_merge_loss_tmp.php 的 F-B 原样拆出（外层 foreach + 臂内嵌 for + 臂尾裸 continue + 兄弟语句 $hit++）。
// 真值：visited=4 hit=2 count_x=4；facet-1 方案 B 落地后 AOT 与 PHP 逐字节等值。

function rc5fb_mk(int $n): array {
    $a = [];
    for ($i = 0; $i < $n; $i++) {
        $a['k' . $i] = $i;
    }
    return $a;
}

$b = rc5fb_mk(4);
$w = 0;
$hit = 0;
$x = [];
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
echo "F-B visited={$w} hit={$hit} count_x=" . count($x) . "\n";
