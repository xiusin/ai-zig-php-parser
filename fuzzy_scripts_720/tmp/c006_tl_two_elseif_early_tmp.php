<?php
// 永久取证探针 AOT-CODEGEN-006 D-2：与形状8 同几何，取**首臂**（$mode==="2"）⇒ 校验
// D 批双臂发射没有把链的首臂尾部接成 fallthrough（若接错会继续执行末臂循环）。
// 真值：输出 T11 b2。

$mode = "2";
if ($mode === "2") {
    echo "T11 b2\n";
} elseif ($mode === "3") {
    echo "T11 b3\n";
} elseif ($mode === "4") {
    echo "T11 b4\n";
} else {
    $hit = 0;
    $sum = 0;
    for ($i = 0; $i < 3; $i++) {
        $hit = $hit + 1;
        $sum = $sum + 1;
    }
    echo "T11 hit={$hit} sum={$sum}\n";
}
