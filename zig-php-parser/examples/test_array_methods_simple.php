<?php

echo "=== Array方法测试（简化版）===\n\n";

// 测试1: 创建数组
echo "1. 创建数组:\n";
$arr = [1, 2, 3, 4, 5];
echo "原始数组: ";
print_r($arr);
echo "\n";

// 测试2: count
echo "2. count测试:\n";
$arr2 = [1, 2, 3, 4, 5];
$count = count($arr2);
echo "数组长度: $count\n\n";

// 测试3: array_reverse
echo "3. array_reverse测试:\n";
$arr3 = [1, 2, 3, 4, 5];
echo "原始: ";
print_r($arr3);
$reversed = array_reverse($arr3);
echo "反转: ";
print_r($reversed);
echo "\n";

// 测试4: array_keys
echo "4. array_keys测试:\n";
$arr4 = [10, 20, 30];
$keys = array_keys($arr4);
echo "键: ";
print_r($keys);
echo "\n";

// 测试5: array_values
echo "5. array_values测试:\n";
$arr5 = [10, 20, 30];
$values = array_values($arr5);
echo "值: ";
print_r($values);
echo "\n";

// 测试6: array_merge
echo "6. array_merge测试:\n";
$arr6a = [1, 2, 3];
$arr6b = [4, 5, 6];
$merged = array_merge($arr6a, $arr6b);
echo "合并: ";
print_r($merged);
echo "\n";

echo "=== Array方法测试完成 ===\n";

?>
