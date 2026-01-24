<?php
// 简单测试：验证求值顺序
$i = 5;
echo "Initial i: ";
echo $i;
echo "\n";

$a = ++$i;
echo "After ++i: i=";
echo $i;
echo ", a=";
echo $a;
echo "\n";

$b = $i++;
echo "After i++: i=";
echo $i;
echo ", b=";
echo $b;
echo "\n";

// 重置测试
$i = 5;
echo "\nReset i to 5\n";

// 分步测试表达式
$x = ++$i;
echo "x = ++i: x=";
echo $x;
echo ", i=";
echo $i;
echo "\n";

$y = $i++;
echo "y = i++: y=";
echo $y;
echo ", i=";
echo $i;
echo "\n";

$z = $x + $y;
echo "z = x + y: z=";
echo $z;
echo "\n";

// 一次性测试
$i = 5;
echo "\nReset i to 5\n";
$result = ++$i + $i++;
echo "result = ++i + i++: result=";
echo $result;
echo ", i=";
echo $i;
echo "\n";
