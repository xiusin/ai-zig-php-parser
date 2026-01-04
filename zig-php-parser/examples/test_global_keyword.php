<?php
echo "=== 测试 global 关键字 ===\n\n";

// 测试1: 基本用法
echo "【测试1】基本用法\n";
$global_var = "Hello";
function test1() {
    global $global_var;
    echo "Inside function: $global_var\n";
    $global_var = "World";
}
test1();
echo "Outside function: $global_var\n\n";

// 测试2: 多个变量
echo "【测试2】多个变量\n";
$var1 = 10;
$var2 = 20;
function test2() {
    global $var1, $var2;
    echo "var1 = $var1, var2 = $var2\n";
    $var1 += 5;
    $var2 += 10;
}
test2();
echo "After function: var1 = $var1, var2 = $var2\n\n";

// 测试3: 不存在的变量
echo "【测试3】不存在的变量\n";
function test3() {
    global $nonexistent;
    echo "nonexistent = ";
    var_dump($nonexistent);
    $nonexistent = "created";
}
test3();
echo "After function: nonexistent = $nonexistent\n\n";

echo "✅ global 关键字测试完成\n";
