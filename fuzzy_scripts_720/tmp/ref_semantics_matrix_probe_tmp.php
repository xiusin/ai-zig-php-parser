<?php
// 永久探针：引用（reference）语义分层对照，用于把「对象属性引用写回失效」定位到具体层。
// 每行都成对输出「容器读回 | 引用变量读回」，PHP 语义下两者必须恒等。
// case1 变量引用      期望 2|2
// case2 数组元素引用  期望 9|9
// case3 对象属性引用  期望 7|7（已实测 AOT 失效）
// case4 静态属性引用  期望 5|5
// case5 属性持变量引用（$c->p = &$v）期望 2|2
// case6 函数 by-ref 形参 期望 42
// case7 foreach by-ref 期望 10,20,30
// case8 二维：数组元素的元素引用 期望 3|3
$x = 1;
$r1 = &$x;
$r1 = 2;
echo "case1=", $x, "|", $r1, "\n";

$a = [1, 2];
$r2 = &$a[0];
$r2 = 9;
echo "case2=", $a[0], "|", $r2, "\n";

$c3 = new stdClass;
$c3->p = 1;
$r3 = &$c3->p;
$r3 = 7;
echo "case3=", $c3->p, "|", $r3, "\n";

class S { public static $v = 1; }
$r4 = &S::$v;
$r4 = 5;
echo "case4=", S::$v, "|", $r4, "\n";

$c5 = new stdClass;
$v5 = 1;
$c5->p = &$v5;
$v5 = 2;
echo "case5=", $c5->p, "|", $v5, "\n";

function f6(&$y) { $y = 42; }
$z6 = 0;
f6($z6);
echo "case6=", $z6, "\n";

$arr7 = [1, 2, 3];
foreach ($arr7 as &$e7) { $e7 *= 10; }
unset($e7);
echo "case7=", implode(',', $arr7), "\n";

$m8 = [['k' => 1]];
$r8 = &$m8[0]['k'];
$r8 = 3;
echo "case8=", $m8[0]['k'], "|", $r8, "\n";
