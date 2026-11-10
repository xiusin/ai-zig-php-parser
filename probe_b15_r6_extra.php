<?php
function byref(&$x) { $x = 88; }
// 已存在元素
$a = ['k' => 1];
byref($a['k']);
var_dump($a);
// 函数内局部数组元素
function local_elem() {
    $arr = ['m' => 5];
    byref($arr['m']);
    byref($arr['n']);
    var_dump($arr);
}
local_elem();
// 内建 str_replace count 未定义（变量形静默）
$r = str_replace('x', 'y', 'xax', $cnt);
var_dump($r, $cnt);
// settype 未定义变量
var_dump(settype($u, 'int'));
var_dump($u);
