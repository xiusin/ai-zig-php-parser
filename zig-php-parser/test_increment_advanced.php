<?php
// 高级测试：递增递减运算符

echo "=== 测试1: 基本功能 ===\n";
$x = 10;
echo "初始值: ";
echo $x;
echo "\n";

echo "前置递增 ++x: ";
echo ++$x;
echo "\n";

echo "当前值: ";
echo $x;
echo "\n";

echo "后置递增 x++: ";
echo $x++;
echo "\n";

echo "当前值: ";
echo $x;
echo "\n";

echo "\n=== 测试2: 连续操作 ===\n";
$y = 5;
echo "初始值: ";
echo $y;
echo "\n";

$result = ++$y + ++$y;
echo "++y + ++y = ";
echo $result;
echo ", y = ";
echo $y;
echo "\n";

echo "\n=== 测试3: 混合操作 ===\n";
$z = 10;
$a = ++$z;
$b = $z++;
$c = --$z;
$d = $z--;
echo "a=";
echo $a;
echo ", b=";
echo $b;
echo ", c=";
echo $c;
echo ", d=";
echo $d;
echo ", z=";
echo $z;
echo "\n";

echo "\n=== 测试4: 在条件中使用 ===\n";
$count = 0;
while ($count < 3) {
    echo "count = ";
    echo $count++;
    echo "\n";
}

echo "\n=== 测试5: 负数递增递减 ===\n";
$neg = -5;
echo "初始值: ";
echo $neg;
echo "\n";

echo "++neg: ";
echo ++$neg;
echo "\n";

echo "++neg: ";
echo ++$neg;
echo "\n";

echo "neg--: ";
echo $neg--;
echo "\n";

echo "最终值: ";
echo $neg;
echo "\n";

echo "\n=== 测试6: 零值操作 ===\n";
$zero = 0;
echo "初始值: ";
echo $zero;
echo "\n";

echo "++zero: ";
echo ++$zero;
echo "\n";

echo "--zero: ";
echo --$zero;
echo "\n";

echo "--zero: ";
echo --$zero;
echo "\n";

echo "最终值: ";
echo $zero;
echo "\n";

echo "\n=== 所有测试完成 ===\n";
