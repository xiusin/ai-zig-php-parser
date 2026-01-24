<?php
// 测试Foreach循环

// 测试1: 基本foreach（只遍历值）
echo "Test 1: Basic foreach\n";
$arr1 = [1, 2, 3, 4, 5];
foreach ($arr1 as $value) {
    echo $value;
    echo " ";
}
echo "\n";

// 测试2: 带键的foreach
echo "Test 2: Foreach with keys\n";
$arr2 = [10, 20, 30];
foreach ($arr2 as $key => $value) {
    echo $key;
    echo ": ";
    echo $value;
    echo "\n";
}

// 测试3: 字符串数组
echo "Test 3: String array\n";
$arr3 = ["apple", "banana", "cherry"];
foreach ($arr3 as $fruit) {
    echo $fruit;
    echo " ";
}
echo "\n";

// 测试4: 嵌套foreach
echo "Test 4: Nested foreach\n";
$arr4 = [[1, 2], [3, 4]];
foreach ($arr4 as $inner) {
    foreach ($inner as $value) {
        echo $value;
        echo " ";
    }
}
echo "\n";

// 测试5: Foreach中使用break
echo "Test 5: Foreach with break\n";
$arr5 = [1, 2, 3, 4, 5];
foreach ($arr5 as $value) {
    if ($value == 3) {
        break;
    }
    echo $value;
    echo " ";
}
echo "\n";

// 测试6: Foreach中使用continue
echo "Test 6: Foreach with continue\n";
$arr6 = [1, 2, 3, 4, 5];
foreach ($arr6 as $value) {
    if ($value == 3) {
        continue;
    }
    echo $value;
    echo " ";
}
echo "\n";

echo "All foreach tests completed!\n";
