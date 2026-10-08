<?php
// 永久探针：外层臂尾丢失四维二分（v3）
// v2 实测：外层 `||` 条件臂 + 臂内「无 else 的 if/elseif 链」，走 if 首臂时臂尾 echo 丢失（rc=0），
//         走 elseif 臂则完整。本探针分离四个变量：
//   E：外层条件为单个 `===`（无 `||`）+ 无 else 内嵌链 + 臂尾 echo
//   F：外层 `||` + 内嵌链「有 else」+ 臂尾 echo
//   G：外层 9 元 `||`（单行）+ 臂体两条 echo（无嵌套链）
//   H：外层 `||` + 内嵌单个 if（无 elseif 无 else）+ 臂尾 echo
$n = isset($argv[1]) ? $argv[1] : 'a';
echo "N=$n\n";

if ($n === 'e1') {
    echo "E-head\n";
    if ($n === 'e1') {
        echo "E-arm-1\n";
    } elseif ($n === 'e2') {
        echo "E-arm-2\n";
    }
    echo "E-tail\n";
} elseif ($n === 'f1' || $n === 'f2') {
    echo "F-head\n";
    if ($n === 'f1') {
        echo "F-arm-1\n";
    } elseif ($n === 'f2') {
        echo "F-arm-2\n";
    } else {
        echo "F-arm-else\n";
    }
    echo "F-tail\n";
} elseif ($n === 'g1' || $n === 'g2' || $n === 'g3' || $n === 'g4'
        || $n === 'g5' || $n === 'g6' || $n === 'g7' || $n === 'g8' || $n === 'g9') {
    echo "G-head\n";
    echo "G-tail\n";
} elseif ($n === 'h1' || $n === 'h2') {
    echo "H-head\n";
    if ($n === 'h1') {
        echo "H-arm-1\n";
    }
    echo "H-tail\n";
} else {
    echo "OTHER\n";
}
