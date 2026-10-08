<?php
// 永久取证探针 AOT-CODEGEN-006 形状2：顶层 if/else（无 elseif），else 臂含 for 循环 + echo。
// 与形状1 差异：去掉 elseif ⇒ 判定三臂结构（if/elseif/else）是否为致损必要条件。
// 真值：输出 T2 hit=3。

$mode = "1";
if ($mode === "2") {
    echo "T2 branch2\n";
} else {
    $hit = 0;
    for ($i = 0; $i < 3; $i++) {
        $hit = $hit + 1;
    }
    echo "T2 hit={$hit}\n";
}
