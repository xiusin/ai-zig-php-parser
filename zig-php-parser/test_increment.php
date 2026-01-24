<?php
// 测试1: 前置递增
$a = 5;
$b = ++$a;
echo "After ++a: a=";
echo $a;
echo ", b=";
echo $b;
echo "\n";

// 测试2: 后置递增
$c = 5;
$d = $c++;
echo "After c++: c=";
echo $c;
echo ", d=";
echo $d;
echo "\n";

// 测试3: 前置递减
$e = 5;
$f = --$e;
echo "After --e: e=";
echo $e;
echo ", f=";
echo $f;
echo "\n";

// 测试4: 后置递减
$g = 5;
$h = $g--;
echo "After g--: g=";
echo $g;
echo ", h=";
echo $h;
echo "\n";

// 测试5: 在表达式中使用
$i = 10;
$j = ++$i + $i++;
echo "Expression: j=";
echo $j;
echo ", i=";
echo $i;
echo "\n";

// 测试6: 循环中使用
$sum = 0;
$k = 0;
while ($k < 5) {
    $sum = $sum + $k;
    $k++;
}
echo "Sum: ";
echo $sum;
echo "\n";
