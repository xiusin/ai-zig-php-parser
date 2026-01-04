<?php
// 测试 .= 操作符
echo "=== 测试 .= 操作符 ===\n\n";

// 测试1：字符串连接
$a = "Hello";
$a .= " World";
echo "测试1: $a\n";
if ($a !== "Hello World") {
    echo "❌ 失败：期望 'Hello World'，得到 '$a'\n";
} else {
    echo "✅ 通过\n";
}
echo "\n";

// 测试2：数字转换为字符串
$b = 123;
$b .= "456";
echo "测试2: $b\n";
if ($b !== "123456") {
    echo "❌ 失败：期望 '123456'，得到 '$b'\n";
} else {
    echo "✅ 通过\n";
}
echo "\n";

// 测试3：布尔值转换为字符串
$c = true;
$c .= " value";
echo "测试3: $c\n";
if ($c !== "1 value") {
    echo "❌ 失败：期望 '1 value'，得到 '$c'\n";
} else {
    echo "✅ 通过\n";
}
echo "\n";

// 测试4：null 转换为字符串
$d = null;
$d .= " is null";
echo "测试4: $d\n";
if ($d !== " is null") {
    echo "❌ 失败：期望 ' is null'，得到 '$d'\n";
} else {
    echo "✅ 通过\n";
}
echo "\n";

// 测试5：连续 .= 操作
$e = "Start";
$e .= " Middle";
$e .= " End";
echo "测试5: $e\n";
if ($e !== "Start Middle End") {
    echo "❌ 失败：期望 'Start Middle End'，得到 '$e'\n";
} else {
    echo "✅ 通过\n";
}
echo "\n";

// 测试6：对象属性 .= 操作
class TestClass {
    public $name = "Initial";
}
$obj = new TestClass();
$obj->name .= " Updated";
echo "测试6: $obj->name\n";
if ($obj->name !== "Initial Updated") {
    echo "❌ 失败：期望 'Initial Updated'，得到 '$obj->name'\n";
} else {
    echo "✅ 通过\n";
}
echo "\n";

echo "=== 所有测试完成 ===\n";
