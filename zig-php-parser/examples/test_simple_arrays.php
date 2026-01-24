<?php
// 简单的数组测试

echo "=== Test 1: 数组创建和访问 ===\n";

$numbers = array(10, 20, 30);
echo "numbers[0] = ";
echo $numbers[0];
echo "\n";

echo "numbers[1] = ";
echo $numbers[1];
echo "\n";

echo "numbers[2] = ";
echo $numbers[2];
echo "\n";

echo "\n=== Test 2: 数组修改 ===\n";

$data = array(1, 2, 3);
echo "Before: data[1] = ";
echo $data[1];
echo "\n";

$data[1] = 99;
echo "After: data[1] = ";
echo $data[1];
echo "\n";

echo "\n=== Test 3: 数组长度 ===\n";

$list = array(1, 2, 3, 4, 5);
$len = count($list);
echo "Array length: ";
echo $len;
echo "\n";

echo "\n=== All array tests completed ===\n";
