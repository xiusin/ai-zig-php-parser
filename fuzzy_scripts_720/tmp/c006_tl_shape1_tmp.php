<?php
// 永久取证探针 AOT-CODEGEN-006 形状1：顶层 if/elseif/else，仅 else 臂含 for 循环 + echo。
// 由 perf001 热点探针的 M1 空输出逆向最小化而来（原形三臂 + 两函数）。
// 真值：else 臂执行 ⇒ 输出 T1 hit=3 sum=3。

$mode = "1";
if ($mode === "2") {
    echo "T1 branch2\n";
} elseif ($mode === "3") {
    echo "T1 branch3\n";
} else {
    $hit = 0;
    $sum = 0;
    for ($i = 0; $i < 3; $i++) {
        $hit = $hit + 1;
        $sum = $sum + 1;
    }
    echo "T1 hit={$hit} sum={$sum}\n";
}
