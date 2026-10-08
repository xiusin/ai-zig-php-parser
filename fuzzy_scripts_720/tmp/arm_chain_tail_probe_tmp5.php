<?php
// 永久探针：臂尾丢失嵌套维度对照（v5）
// v4 实测：外层为 if/elseif 链的臂内，含「if + elseif」二级链且走二级链首臂时，
//          二级链之后的外层臂尾语句零发射（rc=0 静默截断）；二级链若只有单个 if（H 形）则正常。
// 本探针分离嵌套容器：
//   I：顶层直接 if/elseif 链 + 链后语句（对照组，预期正常）
//   J：外层单个 if（无链）内嵌 if/elseif 链 + 链后语句
//   K：外层 if/elseif 链的 elseif 臂内嵌 if/elseif 链 + 链后语句
//   L：外层 if/elseif 链臂内嵌 if/elseif 链，链后还有第二条语句（确认丢失范围是「链后全部」）
$n = isset($argv[1]) ? $argv[1] : 'a';
echo "N=$n\n";

if ($n === 'i1') {
    echo "I-arm-1\n";
} elseif ($n === 'i2') {
    echo "I-arm-2\n";
}
echo "I-after\n";

if ($n === 'j1' || $n === 'j2') {
    if ($n === 'j1') {
        echo "J-arm-1\n";
    } elseif ($n === 'j2') {
        echo "J-arm-2\n";
    }
    echo "J-tail\n";
}

if ($n === 'k1' || $n === 'k2' || $n === 'k3') {
    if ($n === 'k1') {
        echo "K-if\n";
    } elseif ($n === 'k2') {
        if ($n === 'k2') {
            echo "K-arm-1\n";
        } elseif ($n === 'k3') {
            echo "K-arm-2\n";
        }
        echo "K-tail\n";
    } elseif ($n === 'k3') {
        echo "K-third\n";
    }
    echo "K-after\n";
}

if ($n === 'l1' || $n === 'l2') {
    if ($n === 'l1') {
        echo "L-arm-1\n";
    } elseif ($n === 'l2') {
        echo "L-arm-2\n";
    }
    echo "L-tail-1\n";
    echo "L-tail-2\n";
}
echo "END\n";
