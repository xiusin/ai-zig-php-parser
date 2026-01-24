<?php
// 测试内存管理优化
// 这个测试会在循环中创建大量字符串，验证是否有内存泄漏

// 测试1：简单循环中的字符串连接
echo "Test 1: String concatenation in loop\n";
$result = "";
for ($i = 0; $i < 10; $i++) {
    $temp = "Iteration " . $i . "\n";
    $result = $result . $temp;
}
echo $result;

// 测试2：while循环中的临时变量
echo "\nTest 2: Temporary variables in while loop\n";
$count = 0;
while ($count < 5) {
    $msg = "Count: " . $count . "\n";
    echo $msg;
    $count = $count + 1;
}

// 测试3：嵌套循环
echo "\nTest 3: Nested loops\n";
for ($i = 0; $i < 3; $i++) {
    for ($j = 0; $j < 3; $j++) {
        $output = "(" . $i . "," . $j . ") ";
        echo $output;
    }
    echo "\n";
}

echo "\nAll tests completed!\n";
