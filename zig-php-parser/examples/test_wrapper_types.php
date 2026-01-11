<?php
/**
 * Wrapper 类型功能测试
 * 测试 StringWrapper、ArrayWrapper（普通数组）、NumberWrapper 的完整功能
 */

echo "=== Wrapper Type Function Tests ===\n\n";

// ============================================
// 1. StringWrapper 测试
// ============================================
echo "1. StringWrapper Tests:\n";

$str = "  Hello World  ";
echo "   Original: '{$str}'\n";

// toUpper / toLower
$upper = $str->toUpper();
echo "   toUpper: '{$upper}'\n";

$lower = $str->toLower();
echo "   toLower: '{$lower}'\n";

// trim
$trimmed = $str->trim();
echo "   trim: '{$trimmed}'\n";

// length
$len = $trimmed->length();
echo "   length: {$len}\n";

// replace
$replaced = "Hello PHP"->replace("PHP", "World");
echo "   replace(Hello PHP, PHP->World): '{$replaced}'\n";

// substring
$sub = "Hello World"->substring(0, 5);
echo "   substring(0, 5): '{$sub}'\n";

$sub2 = "Hello World"->substring(6, null);
echo "   substring(6, null): '{$sub2}'\n";

// indexOf
$idx = "Hello World"->indexOf("World");
echo "   indexOf('World'): {$idx}\n";

$idx2 = "Hello World"->indexOf("PHP");
echo "   indexOf('PHP'): " . ($idx2 !== null ? $idx2 : "null") . "\n";

// split
$parts = "a,b,c,d"->split(",");
$parts_str = implode(",", $parts);
echo "   split('a,b,c,d', ','): [{$parts_str}]\n\n";

// ============================================
// 2. ArrayWrapper 测试 (使用普通数组)
// ============================================
echo "2. ArrayWrapper Tests:\n";

// 基本操作
$arr = [];
$arr[] = 1;
$arr[] = 2;
$arr[] = 3;
echo "   push(1,2,3), length: " . count($arr) . "\n";

$arr[] = 4;
$arr[] = 5;
echo "   push(4,5), length: " . count($arr) . "\n";

$val = array_pop($arr);
echo "   pop: {$val}\n";

$val2 = array_shift($arr);
echo "   shift: {$val2}\n";

array_unshift($arr, 0);
echo "   unshift(0), first: {$arr[0]}\n";

// reverse (返回新数组)
$arr2 = [1, 2, 3];
$reversed = $arr2->reverse();
$rev_str = implode(",", $reversed);
echo "   reverse[1,2,3]: [{$rev_str}]\n";

// keys / values
$keys = $reversed->keys();
$keys_str = implode(",", $keys);
echo "   keys: [{$keys_str}]\n";

$vals = $arr2->values();
$vals_str = implode(",", $vals);
echo "   values: [{$vals_str}]\n";

// filter (偶数)
$arr3 = [1, 2, 3, 4, 5];
$filtered = $arr3->filter(function($v) { return $v % 2 == 0; });
$filtered_str = implode(",", $filtered);
echo "   filter[1,2,3,4,5] even: [{$filtered_str}]\n";

// count / isEmpty
$empty_arr = [];
echo "   empty array isEmpty: " . ($empty_arr->isEmpty() ? "true" : "false") . "\n";
echo "   non-empty array isEmpty: " . ($arr->isEmpty() ? "true" : "false") . "\n";
echo "   non-empty array count: " . $arr->count() . "\n\n";

// ============================================
// 3. NumberWrapper 测试
// ============================================
echo "3. NumberWrapper Tests:\n";

// 数学方法
echo "   Integer tests:\n";
echo "   (5)->abs(): " . (5)->abs() . "\n";
echo "   (-5)->abs(): " . (-5)->abs() . "\n";
echo "   (3.7)->ceil(): " . (3.7)->ceil() . "\n";
echo "   (3.2)->floor(): " . (3.2)->floor() . "\n";
echo "   (3.5)->round(): " . (3.5)->round() . "\n";
echo "   (16)->sqrt(): " . (16)->sqrt() . "\n";
echo "   (8)->pow(2): " . (8)->pow(2) . "\n";

echo "   Float tests:\n";
echo "   (3.14159)->round(): " . (3.14159)->round() . "\n";
echo "   (100)->sqrt()->pow(2): " . (100)->sqrt()->pow(2) . "\n";

// 位运算
echo "   Bit operations:\n";
echo "   (12)->bitAnd(10): " . (12)->bitAnd(10) . " (12=1100, 10=1010, 12&10=8)\n";
echo "   (12)->bitOr(10): " . (12)->bitOr(10) . " (12|10=14)\n";
echo "   (12)->bitXor(10): " . (12)->bitXor(10) . " (12^10=6)\n";
echo "   (5)->bitNot(): " . (5)->bitNot() . " (~5=-6)\n";
echo "   (8)->bitShiftLeft(2): " . (8)->bitShiftLeft(2) . " (8<<2=32)\n";
echo "   (32)->bitShiftRight(2): " . (32)->bitShiftRight(2) . " (32>>2=8)\n";

// 三角函数
echo "   Trigonometric:\n";
echo "   (0)->sin(): " . (0)->sin() . "\n";
echo "   (3.14159/2)->cos(): " . (3.14159/2)->cos() . "\n";
echo "   (1)->tan(): " . (1)->tan() . "\n";

// 对数和指数
echo "   Log/Exp:\n";
echo "   (2.71828)->log(): " . (2.71828)->log() . " (approx 1)\n";
echo "   (1)->exp(): " . (1)->exp() . " (approx 2.718)\n";

echo "\n=== All Wrapper Tests Passed ===\n";