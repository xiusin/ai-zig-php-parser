<?php
// 永久探针：顶层 if/elseif 链「臂内嵌链 + 臂尾语句」发射丢失取证
// 背景：f004_oop_deep_inheritance_magic.php 因 PHP 侧 readonly 违规被官方回归门
//       以 SKIP|PHP_error_exit=255 拦下（未进入 AOT 编译），排查其替身探针
//       f004_ro_unser_tmp.php 时发现：外层 elseif 臂内的二级 if/elseif 链
//       后几个臂 + 该臂臂尾 echo "DONE" 在生成码中零发射，AOT 仍 rc=0 静默截断。
// 本探针剥离属性语义，只保留控制流结构：外层链 -> 臂内二级链 -> 臂尾语句 -> 外层 else。
$n = isset($argv[1]) ? $argv[1] : 'a';
echo "N=$n\n";

if ($n === 'aa') {
    echo "1\n";
    echo "TAIL1\n";
} elseif ($n === 'bb') {
    echo "2\n";
    echo "TAIL2\n";
} elseif ($n === 'cc' || $n === 'dd' || $n === 'ee'
        || $n === 'ff' || $n === 'gg' || $n === 'hh'
        || $n === 'ii' || $n === 'jj' || $n === 'kk') {
    echo "3-head\n";
    if ($n === 'cc') {
        echo "arm-cc\n";
    } elseif ($n === 'dd') {
        echo "arm-dd\n";
    } elseif ($n === 'ee') {
        echo "arm-ee\n";
    } elseif ($n === 'ff') {
        echo "arm-ff\n";
    } elseif ($n === 'gg') {
        echo "arm-gg\n";
    } elseif ($n === 'hh') {
        echo "arm-hh\n";
    } elseif ($n === 'ii') {
        echo "arm-ii\n";
    } elseif ($n === 'jj') {
        echo "arm-jj\n";
    } elseif ($n === 'kk') {
        echo "arm-kk\n";
    }
    echo "TAIL3\n";
} else {
    echo "OTHER\n";
}
