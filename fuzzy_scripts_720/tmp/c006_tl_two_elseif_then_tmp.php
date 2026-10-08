<?php
// 永久取证探针 AOT-CODEGEN-006 D-1：与形状8 同几何（两级 elseif + 末 else 臂含 for），
// 但取**最深层节点的 then 臂**（$mode==="4"）⇒ 校验 D 批双臂发射的 then 侧：
// 只应打印 T10 b4，循环与 else 臂一行都不能执行。
// 真值：输出 T10 b4。

$mode = "4";
if ($mode === "2") {
    echo "T10 b2\n";
} elseif ($mode === "3") {
    echo "T10 b3\n";
} elseif ($mode === "4") {
    echo "T10 b4\n";
} else {
    $hit = 0;
    $sum = 0;
    for ($i = 0; $i < 3; $i++) {
        $hit = $hit + 1;
        $sum = $sum + 1;
    }
    echo "T10 hit={$hit} sum={$sum}\n";
}
