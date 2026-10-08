<?php
// 永久取证探针 AOT-CODEGEN-006 形状8：两级 elseif 链 + 末尾 else 臂含 for。
// 目的：判定链长度（elseif 计数）是否为放大因子 ⇒ 决定修复是否需覆盖多臂分裂。
// 真值：输出 T8 hit=3 sum=3。

$mode = "1";
if ($mode === "2") {
    echo "T8 b2\n";
} elseif ($mode === "3") {
    echo "T8 b3\n";
} elseif ($mode === "4") {
    echo "T8 b4\n";
} else {
    $hit = 0;
    $sum = 0;
    for ($i = 0; $i < 3; $i++) {
        $hit = $hit + 1;
        $sum = $sum + 1;
    }
    echo "T8 hit={$hit} sum={$sum}\n";
}
