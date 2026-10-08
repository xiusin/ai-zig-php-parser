<?php
// 永久取证探针 AOT-CODEGEN-006 形状4：for 循环在 elseif 臂（而非 else 臂）。
// 目的：判定丢失是否只发生在 else 臂，还是 elseif 臂同样丢（⇒ 定位「谁被 merge 吸收」）。
// 真值：输出 T4 hit=3 sum=3。

$mode = "2";
if ($mode === "1") {
    echo "T4 branch1\n";
} elseif ($mode === "2") {
    $hit = 0;
    $sum = 0;
    for ($i = 0; $i < 3; $i++) {
        $hit = $hit + 1;
        $sum = $sum + $i;
    }
    echo "T4 hit={$hit} sum={$sum}\n";
} else {
    echo "T4 else\n";
}
