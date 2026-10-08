<?php
// 永久取证探针 AOT-CODEGEN-006 形状3：顶层 if/elseif/else，else 臂只有 echo（无循环）。
// 目的：界定致损是「整条 else 臂丢失」还是「臂内 for 循环发射失败连带臂尾 echo」。
// 真值：输出 T3 else。

$mode = "1";
if ($mode === "2") {
    echo "T3 branch2\n";
} elseif ($mode === "3") {
    echo "T3 branch3\n";
} else {
    echo "T3 else\n";
}
