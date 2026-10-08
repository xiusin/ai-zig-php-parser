<?php
// 永久取证探针 AOT-CODEGEN-006 形状5：else 臂内嵌 while（而非 for）。
// 目的：判定循环类型是否为必要条件 ⇒ 决定修复是否要覆盖三生成器对称面。
// 真值：输出 T5 hit=3 sum=3。

$mode = "1";
if ($mode === "2") {
    echo "T5 branch2\n";
} elseif ($mode === "3") {
    echo "T5 branch3\n";
} else {
    $hit = 0;
    $sum = 0;
    $i = 0;
    while ($i < 3) {
        $hit = $hit + 1;
        $sum = $sum + $i;
        $i = $i + 1;
    }
    echo "T5 hit={$hit} sum={$sum}\n";
}
