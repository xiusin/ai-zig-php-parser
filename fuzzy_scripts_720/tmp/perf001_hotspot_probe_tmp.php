<?php
// 永久取证探针：AOT-PERF-001 运行期热点归因（sample 采样 + 源码级消融，不改发射侧一行代码）。
// 目的：把工单 §3 的三条推断（H1 全局按名寻址 / H2 装箱 Value / H3 每迭代 setSourceLocation）
//       从「生成码静态阅读」升级为「运行期实测占比」。
// 用法：php 与 aot 二进制均传 mode；AOT 需 --optimize=release-fast 才能采到与语料同档位的剖面。
//   mode=1 顶层全局循环（发射为 getGlobalVar/setGlobalVar ⇒ 暴露 H1）
//   mode=2 函数内局部循环（发射为局部槽 ⇒ mode1-mode2 差即 H1 净成本；循环体逐字同构）
//   mode=3 数组写循环（暴露 Elements 插入/COW 与 php_add 装箱路径 ⇒ H2）
// 真值输出带各自末值，用于确认三种 mode 计算的是同一道题，防止「跑得慢但算得少」的假归因。

$mode = isset($argv[1]) ? (string)$argv[1] : "1";
$n = 30000000;

function perf001_local(int $n): array {
    $g = 0;
    $h = 0;
    for ($i = 0; $i < $n; $i++) {
        $g = $g + $i;
        $h = $h + 3;
    }
    return [$g, $h];
}

function perf001_array(int $n): int {
    $a = [];
    $s = 0;
    for ($i = 0; $i < $n; $i++) {
        $a[$i] = $i + 1;
        $s = $s + $i;
    }
    return count($a) + $s;
}

if ($mode === "2") {
    $r = perf001_local($n);
    echo "M2 g={$r[0]} h={$r[1]}\n";
} elseif ($mode === "3") {
    echo "M3 sum=" . perf001_array($n) . "\n";
} else {
    $g = 0;
    $h = 0;
    for ($i = 0; $i < $n; $i++) {
        $g = $g + $i;
        $h = $h + 3;
    }
    echo "M1 g={$g} h={$h}\n";
}
