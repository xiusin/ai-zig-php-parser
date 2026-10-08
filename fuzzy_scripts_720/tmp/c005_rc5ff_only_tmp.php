<?php
// 永久取证探针：AOT-CODEGEN-005 RC-5 facet-2 单形隔离（F-F）。
// 从 c005_rc5_merge_loss_tmp.php 的 F-F 原样拆出（外层 foreach + 臂内嵌 while + 臂尾裸 continue + 兄弟语句 $hit++）。
// 拆出目的：八形合于一文件时整体比对恒为 DIFFERS，单形文件才能把「过执行」逐字节门禁化。
// 真值：visited=4 hit=2 count_x=4（foreach 4 轮，前 2 轮走臂并 continue 跳过 $hit++，后 2 轮执行 $hit++）。

function rc5ff_mk(int $n): array {
    $a = [];
    for ($i = 0; $i < $n; $i++) {
        $a['k' . $i] = $i;
    }
    return $a;
}

$b = rc5ff_mk(4);
$w = 0;
$hit = 0;
$x = [];
foreach ($b as $key => $val) {
    $w++;
    if ($w < 3) {
        $k = 0;
        while ($k < 2) {
            $x[$w . "_" . $k] = $k;
            $k++;
        }
        continue;
    }
    $hit++;
}
echo "F-F visited={$w} hit={$hit} count_x=" . count($x) . "\n";
