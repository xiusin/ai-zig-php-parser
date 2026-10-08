<?php
// 永久取证探针：AOT-CODEGEN-005 RC-5 facet-2 单形隔离（F-H）。
// 从 c005_rc5_merge_loss_tmp.php 的 F-H 原样拆出（外层 for + 臂内嵌 for + 臂尾裸 continue + 兄弟语句 $hit++）。
// 拆出目的：与 F-F（外层 foreach + 内嵌 while）成对，判定丢失是否 foreach/while 专属。
// 真值：hit=1 count_x=6（外层 4 轮，前 3 轮走臂并 continue 跳过 $hit++，仅第 4 轮执行 $hit++）。

$hit = 0;
$x = [];
for ($i = 0; $i < 4; $i++) {
    $w = $i;
    if ($w < 3) {
        for ($j = 0; $j < 2; $j++) {
            $x[$i . "_" . $j] = $j;
        }
        continue;
    }
    $hit++;
}
echo "F-H hit={$hit} count_x=" . count($x) . "\n";
