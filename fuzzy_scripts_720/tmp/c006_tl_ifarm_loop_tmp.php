<?php
// 永久取证探针 AOT-CODEGEN-006 形状9：两级链中**首个 if 臂**含 for（对照形状1 的 else 臂、形状4 的 elseif 臂）。
// 目的：补全「臂位（if / elseif / else）」维度 ⇒ 判定丢失是否只在 merge 之后的臂。
// 真值：输出 T9 hit=3 sum=3。

$mode = "1";
if ($mode === "1") {
    $hit = 0;
    $sum = 0;
    for ($i = 0; $i < 3; $i++) {
        $hit = $hit + 1;
        $sum = $sum + 1;
    }
    echo "T9 hit={$hit} sum={$sum}\n";
} elseif ($mode === "2") {
    echo "T9 b2\n";
} else {
    echo "T9 else\n";
}
