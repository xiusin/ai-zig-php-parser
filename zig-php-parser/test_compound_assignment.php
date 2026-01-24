<?php
// 测试复合赋值运算符

// 1. 加法赋值 +=
$a = 10;
$a += 5;
echo "a += 5: ";
echo $a;
echo "\n";

// 2. 减法赋值 -=
$b = 20;
$b -= 8;
echo "b -= 8: ";
echo $b;
echo "\n";

// 3. 乘法赋值 *=
$c = 3;
$c *= 4;
echo "c *= 4: ";
echo $c;
echo "\n";

// 4. 除法赋值 /=
$d = 100;
$d /= 5;
echo "d /= 5: ";
echo $d;
echo "\n";

// 5. 取模赋值 %=
$e = 17;
$e %= 5;
echo "e %= 5: ";
echo $e;
echo "\n";

// 6. 字符串连接赋值 .=
$f = "Hello";
$f .= " World";
echo "f .= ' World': ";
echo $f;
echo "\n";

// 7. 混合测试
$g = 100;
$g += 50;  // 150
$g -= 30;  // 120
$g *= 2;   // 240
$g /= 4;   // 60
$g %= 7;   // 4
echo "Mixed operations result: ";
echo $g;
echo "\n";

// 8. 浮点数测试
$h = 10.5;
$h += 2.5;
echo "Float += : ";
echo $h;
echo "\n";

$h *= 2.0;
echo "Float *= : ";
echo $h;
echo "\n";

echo "All tests completed!\n";
