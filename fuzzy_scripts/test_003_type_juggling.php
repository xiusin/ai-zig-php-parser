<?php
// 类型自动转换测试

// 字符串与数字转换
echo "字符串+数字: " . ("5" + 3) . "\n";
echo "数字+字符串: " . (10 + "20") . "\n";
echo "非数字字符串转数字: " . ("abc" + 1) . "\n";
echo "混合字符串转数字: " . ("10abc" + 5) . "\n";
echo "浮点数字符串: " . ("3.14" * 2) . "\n";

// 布尔转换
echo "int转bool: " . var_export((bool)0, true) . " " . var_export((bool)1, true) . " " . var_export((bool)-1, true) . "\n";
echo "string转bool: " . var_export((bool)"", true) . " " . var_export((bool)"0", true) . " " . var_export((bool)"false", true) . "\n";
echo "array转bool: " . var_export((bool)[], true) . " " . var_export((bool)[0], true) . "\n";
echo "null转bool: " . var_export((bool)null, true) . "\n";

// 整数转换
echo "float转int: " . ((int)3.7) . " " . ((int)(-3.7)) . " " . ((int)3.0) . "\n";
echo "string转int: " . ((int)"42") . " " . ((int)"3.14") . " " . ((int)"abc") . "\n";
echo "bool转int: " . ((int)true) . " " . ((int)false) . "\n";

// 浮点转换
echo "int转float: " . ((float)42) . "\n";
echo "string转float: " . ((float)"3.14") . " " . ((float)".5") . "\n";

// 字符串转换
echo "int转string: " . ((string)42) . " " . ((string)(-99)) . "\n";
echo "float转string: " . ((string)3.14159) . "\n";
echo "bool转string: " . ((string)true) . " " . ((string)false) . "\n";
echo "array转string: ";
try { echo (string)[1,2,3]; } catch (Error $e) { echo "Error: " . $e->getMessage(); }
echo "\n";

// 数组转换
echo "标量转数组: " . var_export((array)42, true) . "\n";
echo "null转数组: " . var_export((array)null, true) . "\n";

// 对象转换
class TestObj { public $x = 10; }
$obj = new TestObj();
echo "array转对象属性: " . var_export((array)$obj, true) . "\n";

// 复杂混合运算
echo "混合运算1: " . (true + "2" + 3.0) . "\n";
echo "混合运算2: " . ("10.5" + (int)"5.9") . "\n";
echo "混合运算3: " . (false . true) . "\n";
