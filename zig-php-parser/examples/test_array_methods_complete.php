<?php

echo "=== Array方法测试 ===\n\n";

// 测试1: 创建数组
echo "1. 创建数组:\n";
$arr = array(1, 2, 3, 4, 5);
echo "原始数组: ";
print_r($arr);
echo "\n";

// 测试2: array_push
echo "2. array_push测试:\n";
$arr2 = array(1, 2, 3);
echo "原始: ";
print_r($arr2);
array_push($arr2, 4, 5);
echo "添加4,5后: ";
print_r($arr2);
echo "\n";

// 测试3: array_pop
echo "3. array_pop测试:\n";
$arr3 = array(1, 2, 3, 4);
echo "原始: ";
print_r($arr3);
$last = array_pop($arr3);
echo "弹出: $last\n";
echo "弹出后: ";
print_r($arr3);
echo "\n";

// 测试4: array_reverse
echo "4. array_reverse测试:\n";
$arr4 = array(1, 2, 3, 4, 5);
echo "原始: ";
print_r($arr4);
$reversed = array_reverse($arr4);
echo "反转: ";
print_r($reversed);
echo "\n";

// 测试5: array_keys
echo "5. array_keys测试:\n";
$arr5 = array(10, 20, 30);
echo "原始: ";
print_r($arr5);
$keys = array_keys($arr5);
echo "键: ";
print_r($keys);
echo "\n";

// 测试6: array_values
echo "6. array_values测试:\n";
$arr6 = array(10, 20, 30);
echo "原始: ";
print_r($arr6);
$values = array_values($arr6);
echo "值: ";
print_r($values);
echo "\n";

// 测试7: count
echo "7. count测试:\n";
$arr7 = array(1, 2, 3, 4, 5);
echo "数组: ";
print_r($arr7);
$count = count($arr7);
echo "长度: $count\n\n";

// 测试8: array_merge
echo "8. array_merge测试:\n";
$arr8a = array(1, 2, 3);
$arr8b = array(4, 5, 6);
echo "数组1: ";
print_r($arr8a);
echo "数组2: ";
print_r($arr8b);
$merged = array_merge($arr8a, $arr8b);
echo "合并: ";
print_r($merged);
echo "\n";

echo "=== Array方法测试完成 ===\n";

?>
