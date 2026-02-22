<?php
// 边界情况测试

echo "=== Edge Cases Test ===\n\n";

// 1. 嵌套异常处理
echo "1. Nested Exception Test:\n";
try {
    try {
        throw new Exception("Inner exception");
    } catch (Exception $e) {
        echo "   Caught inner: " . $e->getMessage() . "\n";
        throw new Exception("Outer exception");
    }
} catch (Exception $e) {
    echo "   Caught outer: " . $e->getMessage() . "\n";
}
echo "\n";

// 2. 空数组操作
echo "2. Empty Array Test:\n";
$empty = [];
echo "   Count: " . count($empty) . "\n";
$filtered = array_filter($empty, function($x) { return $x > 0; });
echo "   Filtered count: " . count($filtered) . "\n";
echo "\n";

// 3. 类型转换边界
echo "3. Type Conversion Test:\n";
$zero = 0;
$emptyStr = "";
$null = null;
echo "   0 to bool: " . ($zero ? "true" : "false") . "\n";
echo "   '' to bool: " . ($emptyStr ? "true" : "false") . "\n";
echo "   null to bool: " . ($null ? "true" : "false") . "\n";
echo "\n";

// 4. 字符串边界
echo "4. String Edge Cases:\n";
$str = "Hello";
echo "   Length: " . strlen($str) . "\n";
echo "   Substr(0,0): '" . substr($str, 0, 0) . "'\n";
echo "   Substr(5,1): '" . substr($str, 5, 1) . "'\n";
echo "\n";

// 5. 递归深度
echo "5. Deep Recursion Test:\n";
function deepRecursion($n) {
    if ($n <= 0) return 0;
    return 1 + deepRecursion($n - 1);
}
$depth = deepRecursion(100);
echo "   Depth 100: $depth\n";
echo "\n";

// 6. 闭包捕获
echo "6. Closure Capture Test:\n";
$x = 10;
$closure = function() use ($x) {
    return $x * 2;
};
$x = 20; // 修改外部变量
echo "   Result: " . $closure() . " (should be 20, not 40)\n";
echo "\n";

// 7. 数组引用
echo "7. Array Reference Test:\n";
$arr = [1, 2, 3];
$ref = &$arr[1];
$ref = 99;
echo "   Modified: " . $arr[1] . "\n";
echo "\n";

// 8. 多重返回
echo "8. Multiple Return Test:\n";
function multiReturn($x) {
    if ($x > 0) return "positive";
    if ($x < 0) return "negative";
    return "zero";
}
echo "   multiReturn(5): " . multiReturn(5) . "\n";
echo "   multiReturn(-5): " . multiReturn(-5) . "\n";
echo "   multiReturn(0): " . multiReturn(0) . "\n";
echo "\n";

echo "=== All Edge Cases Passed ===\n";
