<?php
// 永久探针：elseif 多行 `||` 条件臂丢失二分（v2 双臂）
// 由 arm_chain_tail_probe_tmp.php 首次复现：外层 elseif 的条件跨物理行换行时，
// 整臂（含臂头 echo、内嵌二级链、臂尾 echo）乃至外层 else 臂在生成码中零发射，AOT rc=0。
// 本探针在单次编译内并列三形，分离「条件换行」与「臂内嵌链」两个变量：
//   A 形：条件写在同一行 + 臂内嵌二级 if/elseif 链 + 臂尾 echo
//   B 形：条件跨行换行 + 臂体仅两条 echo（无嵌套链）
//   C 形：条件写在同一行 + 臂体仅两条 echo（对照组）
$n = isset($argv[1]) ? $argv[1] : 'a';
echo "N=$n\n";

if ($n === 'b1' || $n === 'b2') {
    echo "A-head\n";
    if ($n === 'b1') {
        echo "A-arm-1\n";
    } elseif ($n === 'b2') {
        echo "A-arm-2\n";
    }
    echo "A-tail\n";
} elseif ($n === 'c1'
        || $n === 'c2') {
    echo "B-head\n";
    echo "B-tail\n";
} elseif ($n === 'd1' || $n === 'd2') {
    echo "C-head\n";
    echo "C-tail\n";
} else {
    echo "OTHER\n";
}
