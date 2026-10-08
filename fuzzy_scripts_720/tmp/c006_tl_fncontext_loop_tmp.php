<?php
// 永久取证探针 AOT-CODEGEN-006 形状7：同形状1 的几何放进**函数体**内（非顶层脚本体）。
// 目的：判定丢失是否为顶层脚本体专属 ⇒ 区分 tryGenerateFromLabels 顶层路径与函数 label-driven 路径。
// 真值：输出 T7 hit=3 sum=3。

function c006_tl_f7(string $mode): string {
    if ($mode === "2") {
        return "T7 branch2\n";
    } elseif ($mode === "3") {
        return "T7 branch3\n";
    } else {
        $hit = 0;
        $sum = 0;
        for ($i = 0; $i < 3; $i++) {
            $hit = $hit + 1;
            $sum = $sum + 1;
        }
        return "T7 hit={$hit} sum={$sum}\n";
    }
}

echo c006_tl_f7("1");
