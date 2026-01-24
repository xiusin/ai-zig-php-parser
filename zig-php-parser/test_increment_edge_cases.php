<?php
// 边界情况测试

// 测试1: 零值
echo "Test 1: Zero value\n";
$a = 0;
echo "++0: ";
echo ++$a;
echo "\n";

$b = 0;
echo "0++: ";
echo $b++;
echo ", after: ";
echo $b;
echo "\n";

// 测试2: 负数
echo "\nTest 2: Negative numbers\n";
$c = -5;
echo "++-5: ";
echo ++$c;
echo "\n";

$d = -5;
echo "-5++: ";
echo $d++;
echo ", after: ";
echo $d;
echo "\n";

// 测试3: 多次递增
echo "\nTest 3: Multiple increments\n";
$e = 0;
echo "Start: ";
echo $e;
echo "\n";
$e++;
$e++;
$e++;
echo "After 3x++: ";
echo $e;
echo "\n";

// 测试4: 混合使用
echo "\nTest 4: Mixed usage\n";
$f = 10;
$g = ++$f + --$f;
echo "f=";
echo $f;
echo ", g=";
echo $g;
echo "\n";

// 测试5: 在条件中使用
echo "\nTest 5: In conditions\n";
$h = 0;
while ($h++ < 3) {
    echo "h=";
    echo $h;
    echo " ";
}
echo "\n";

// 测试6: 连续后置
echo "\nTest 6: Consecutive postfix\n";
$i = 5;
$j = $i++ + $i++ + $i++;
echo "i=";
echo $i;
echo ", j=";
echo $j;
echo "\n";

echo "\nAll edge case tests completed!\n";
