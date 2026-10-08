<?php
/**
 * AOT-REF-004 §6.1 永久取证探针（勿删）：内建回调族的「引用形参实参装填」普查
 *
 * 目的 = 定死哪些内建高阶函数在把回调实参交给 callee 前做了 make_ref。
 *   已知：array_walk 已装填（runtime_lib_template.zig:25566/25569）⇒ 对照绿。
 *   待测：array_walk_recursive / array_map / array_filter / usort / array_reduce。
 *
 * 选形方式 = $argv[1]（一次编译、N 次运行；崩溃形会杀进程，逐形编译不可行）。
 * 每个 case 都让回调声明引用形参并尝试写回，据此区分三态：
 *   ① 装填正确 ⇒ 与 PHP 逐字节等值；
 *   ② 未装填但 callee 只读 ⇒ 输出仍可能对（写回丢失属静默分歧）；
 *   ③ 未装填且 callee 对空值写入 ⇒ AOT 段错误（rc=139），PHP 至多 Warning。
 *
 * 复测：见 docs/known-issues/AOT-REF-004-dynamic-call-byref-arg-not-made.md §5
 */

$shape = $argv[1] ?? 'walkrec_scalar';

switch ($shape) {
    // ① array_walk：已装填（REF-004 主探针的 CTRL 内建形），此处作逐字节对照锚
    case 'ctrl_walk':
        $a = ['x' => 1, 'y' => 2];
        array_walk($a, function (mixed &$v, string $k): void {
            $v = $v * 10;
        });
        echo "SHAPE=ctrl_walk a=" . json_encode($a) . "\n";
        break;

    // ② array_walk_recursive：标量叶子写回
    case 'walkrec_scalar':
        $a = ['x' => 1, 'y' => 2];
        array_walk_recursive($a, function (mixed &$v, string $k): void {
            $v = $v * 10;
        });
        echo "SHAPE=walkrec_scalar a=" . json_encode($a) . "\n";
        break;

    // ③ array_walk_recursive：嵌套数组叶子写回（callee 只改叶子，不新建元素）
    case 'walkrec_nested':
        $a = ['p' => [1, 2], 'q' => [3]];
        array_walk_recursive($a, function (mixed &$v, string $k): void {
            $v = $v + 100;
        });
        echo "SHAPE=walkrec_nested a=" . json_encode($a) . "\n";
        break;

    // ④ array_map：回调声明引用形参 + 写回（PHP 侧预期 Warning「value given」）
    case 'map_ref':
        $a = [1, 2];
        $r = array_map(function (mixed &$v): mixed {
            $v = $v + 5;
            return $v;
        }, $a);
        echo "SHAPE=map_ref r=" . json_encode($r) . " a=" . json_encode($a) . "\n";
        break;

    // ⑤ array_filter：回调声明引用形参、仅读
    case 'filter_ref':
        $a = [1, 2, 3];
        $r = array_filter($a, function (mixed &$v): bool {
            return $v > 1;
        });
        echo "SHAPE=filter_ref r=" . json_encode($r) . "\n";
        break;

    // ⑥ usort：比较回调声明 array 引用形参 + 向形参追加元素（崩溃候选）
    case 'usort_ref':
        $a = [[2], [1]];
        usort($a, function (array &$x, array &$y): int {
            $x[] = 9;
            return $x[0] <=> $y[0];
        });
        echo "SHAPE=usort_ref a=" . json_encode($a) . "\n";
        break;

    // ⑦ array_reduce：回调声明引用形参 + 写回累加器（崩溃/静默分歧候选）
    case 'reduce_ref':
        $a = [1, 2];
        $s = array_reduce($a, function (mixed &$c, mixed &$v): mixed {
            $c = (int) $c + $v;
            return $c;
        }, 0);
        echo "SHAPE=reduce_ref s=" . json_encode($s) . "\n";
        break;

    default:
        echo "SHAPE=unknown " . $shape . "\n";
        break;
}
