<?php
// 永久取证探针 AOT-CODEGEN-006 形状6：形状1 + if 链之后一条顶层尾语句。
// 目的：区分「else 臂整块丢失」与「臂丢失并连带吞掉链尾语句」；同时给出口边/merge 归属提供第二条读数。
// 真值：输出两行 —— T6 hit=3 sum=3 与 T6 tail。

$mode = "1";
if ($mode === "2") {
    echo "T6 branch2\n";
} elseif ($mode === "3") {
    echo "T6 branch3\n";
} else {
    $hit = 0;
    $sum = 0;
    for ($i = 0; $i < 3; $i++) {
        $hit = $hit + 1;
        $sum = $sum + 1;
    }
    echo "T6 hit={$hit} sum={$sum}\n";
}
echo "T6 tail\n";
