<?php
// 基础变量与类型测试
$a = 42;
$b = 3.14159;
$c = "hello world";
$d = true;
$e = null;
$f = [1, 2, 3];
$g = ['key' => 'value', 'num' => 123];

// 复杂变量名
${'var' . '_name'} = "dynamic";
$$a = "indirect";

echo "a=" . var_export($a, true) . "\n";
echo "b=" . var_export($b, true) . "\n";
echo "c=" . var_export($c, true) . "\n";
echo "d=" . var_export($d, true) . "\n";
echo "e=" . var_export($e, true) . "\n";
echo "f=" . var_export($f, true) . "\n";
echo "g=" . var_export($g, true) . "\n";
echo "dynamic=" . $var_name . "\n";
echo "indirect=" . ${'42'} . "\n";
