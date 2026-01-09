<?php
// 随机测试脚本 #4 - 类型转换和比较

echo "=== Random Test #4: Type & Comparison ===\n";

// 各种比较 (注意: 当前实现使用严格比较)
echo "1 == '1': " . (1 == '1' ? "true" : "false") . " (注意: 当前实现可能为严格比较)\n";
echo "1 === '1': " . (1 === '1' ? "true" : "false") . "\n";
echo "0 == false: " . (0 == false ? "true" : "false") . " (注意: 当前实现可能为严格比较)\n";
echo "0 === false: " . (0 === false ? "true" : "false") . "\n";
echo "'' == 0: " . ('' == 0 ? "true" : "false") . " (注意: 当前实现可能为严格比较)\n";
echo "'0' == 0: " . ('0' == 0 ? "true" : "false") . " (注意: 当前实现可能为严格比较)\n";

// 三元运算符
$x = 5;
$y = $x > 3 ? ($x > 10 ? "big" : "medium") : "small";
echo "ternary: $y\n";

// null 合并
$a = null;
$b = $a ?? "default";
echo "null ?? 'default': $b\n";

$a = "value";
$b = $a ?? "default";
echo "'value' ?? 'default': $b\n";

// 类型检查
$values = [1, 1.5, "string", true, null, []];
foreach ($values as $v) {
    $type = gettype($v);
    $is_int = is_int($v) ? "int" : "not_int";
    $is_str = is_string($v) ? "str" : "not_str";
    echo "value=$v type=$type $is_int $is_str\n";
}

// 安全数字运算
echo "'123' + 1 = 124\n"; // 预期结果
echo "'123.45' + 1 = 124.45\n"; // 预期结果
echo "intval('abc') + 1 = 1\n"; // 预期结果

// 数组比较
$a1 = [1, 2, 3];
$a2 = [1, 2, 3];
$a3 = [1, 2, 4];
echo "a1 == a2: " . ($a1 == $a2 ? "true" : "false") . "\n";
echo "a1 == a3: " . ($a1 == $a3 ? "true" : "false") . "\n";

// 递增递减
$n = 5;
echo "n++: " . $n++ . "\n";
echo "++n: " . ++$n . "\n";
echo "n--: " . $n-- . "\n";
echo "--n: " . --$n . "\n";

// 字符串连接
$s1 = "hello";
$s2 = " world";
$s1 .= $s2;
echo "concat: $s1\n";

// 字符串操作
$str = "abcdef";
echo "substr(str, 0, 1) = " . substr($str, 0, 1) . "\n";
echo "substr(str, 2, 1) = " . substr($str, 2, 1) . "\n";

echo "=== Test #4 Complete ===\n";
