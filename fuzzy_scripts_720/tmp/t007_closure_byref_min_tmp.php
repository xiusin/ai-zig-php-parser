<?php
/**
 * 永久最小探针（闭包 + 引用形参 ⇒ 默认档段错误 rc=139）
 *
 * 来源：t007_refparam_noninline_geom_tmp.php 六形分离实测 ——
 *   ①实例方法引用形参 ②实例方法引用形参+默认值 ③静态方法引用形参
 *   ④引用+普通形参混排 ⑤两引用形参互换 ⇒ 全部与 PHP 逐字节等值
 *   ⑥闭包 function(array &$a) ⇒ M5 之后无输出，RUN rc=139（SIGSEGV）
 * ⇒ 崩溃面 = 闭包（独立 Function，current_has_this_param=false）的引用形参装填，与函数内联无关。
 *
 * 本文件的对照形（CTRL）用全局函数同样的 `array &$a`，必须先输出 CTRL 行，
 * 这样「CTRL 有 / CLOSURE 无」即可一眼判定崩溃点在闭包调用而非按引用传参本身。
 */

function t007ctrl(array &$a): void
{
    $a[] = 9;
}

$ca = [1, 2];
t007ctrl($ca);
echo "CTRL count=" . count($ca) . " last=" . $ca[2] . "\n";

$cl = function (array &$a): void {
    $a[] = 42;
};

$cb = [1];
$cl($cb);
echo "CLOSURE count=" . count($cb) . " last=" . $cb[1] . "\n";

echo "DONE\n";
