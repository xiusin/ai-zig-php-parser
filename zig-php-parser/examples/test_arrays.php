<?php
// 测试数组功能

echo "=== Test 1: 数组创建 ===\n";

$arr = array();
echo "Empty array created\n";

$arr2 = array(1, 2, 3, 4, 5);
echo "Array with 5 elements created\n";

echo "\n=== Test 2: 数组访问 ===\n";

$numbers = array(10, 20, 30, 40, 50);
echo "numbers[0] = " . $numbers[0] . "\n";
echo "numbers[2] = " . $numbers[2] . "\n";
echo "numbers[4] = " . $numbers[4] . "\n";

echo "\n=== Test 3: 数组修改 ===\n";

$data = array(1, 2, 3);
echo "Before: data[1] = " . $data[1] . "\n";
$data[1] = 99;
echo "After: data[1] = " . $data[1] . "\n";

echo "\n=== Test 4: 数组追加 ===\n";

$list = array();
array_push($list, 10);
array_push($list, 20);
array_push($list, 30);
echo "Array size after push: " . count($list) . "\n";
echo "list[0] = " . $list[0] . "\n";
echo "list[1] = " . $list[1] . "\n";
echo "list[2] = " . $list[2] . "\n";

echo "\n=== Test 5: 数组弹出 ===\n";

$stack = array(1, 2, 3, 4, 5);
echo "Before pop: size = " . count($stack) . "\n";
$last = array_pop($stack);
echo "Popped value: " . $last . "\n";
echo "After pop: size = " . count($stack) . "\n";

echo "\n=== Test 6: 关联数组 ===\n";

$person = array();
$person["name"] = "Alice";
$person["age"] = 30;
$person["city"] = "Beijing";

echo "person[\"name\"] = " . $person["name"] . "\n";
echo "person[\"age\"] = " . $person["age"] . "\n";
echo "person[\"city\"] = " . $person["city"] . "\n";

echo "\n=== Test 7: 数组长度 ===\n";

$empty = array();
$small = array(1, 2, 3);
$large = array(1, 2, 3, 4, 5, 6, 7, 8, 9, 10);

echo "Empty array count: " . count($empty) . "\n";
echo "Small array count: " . count($small) . "\n";
echo "Large array count: " . count($large) . "\n";

echo "\n=== Test 8: 数组元素检查 ===\n";

$fruits = array("apple", "banana", "orange");
echo "in_array(\"banana\", fruits): " . (in_array("banana", $fruits) ? "true" : "false") . "\n";
echo "in_array(\"grape\", fruits): " . (in_array("grape", $fruits) ? "true" : "false") . "\n";

echo "\n=== All array tests completed ===\n";
