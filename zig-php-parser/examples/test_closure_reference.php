<?php
echo "=== 测试闭包引用捕获 ===\n\n";

// 测试1: 值捕获
echo "【测试1】值捕获\n";
$var1 = 10;
$closure1 = function() use ($var1) {
    echo "Inside closure: var1 = $var1\n";
    $var1 = 20;
    echo "Modified inside closure: var1 = $var1\n";
};
$closure1();
echo "Outside closure: var1 = $var1\n\n";

// 测试2: 引用捕获
echo "【测试2】引用捕获\n";
$var2 = 10;
$closure2 = function() use (&$var2) {
    echo "Inside closure: var2 = $var2\n";
    $var2 = 20;
    echo "Modified inside closure: var2 = $var2\n";
};
$closure2();
echo "Outside closure: var2 = $var2\n\n";

// 测试3: 多个变量混合捕获
echo "【测试3】多个变量混合捕获\n";
$val1 = 100;
$val2 = 200;
$val3 = 300;
$closure3 = function() use ($val1, &$val2, $val3) {
    echo "Inside closure: val1=$val1, val2=$val2, val3=$val3\n";
    $val1 = 110;
    $val2 = 220;
    $val3 = 330;
    echo "Modified inside closure: val1=$val1, val2=$val2, val3=$val3\n";
};
$closure3();
echo "Outside closure: val1=$val1, val2=$val2, val3=$val3\n\n";

echo "✅ 闭包引用捕获测试完成\n";