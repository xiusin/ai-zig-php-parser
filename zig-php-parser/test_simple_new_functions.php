<?php
// 简单测试新函数

echo "=== 测试新字符串函数 ===\n";

// 1. strrev
$reversed = strrev("hello");
echo "strrev('hello'): ";
echo $reversed;
echo "\n";

// 2. str_repeat
$repeated = str_repeat("ab", 3);
echo "str_repeat('ab', 3): ";
echo $repeated;
echo "\n";

// 3. ucfirst
$ucfirst = ucfirst("hello");
echo "ucfirst('hello'): ";
echo $ucfirst;
echo "\n";

echo "\n=== 测试新数学函数 ===\n";

// 4. sin
$sin_val = sin(0);
echo "sin(0): ";
echo $sin_val;
echo "\n";

// 5. pow
$power = pow(2, 3);
echo "pow(2, 3): ";
echo $power;
echo "\n";

// 6. pi
$pi_val = pi();
echo "pi(): ";
echo $pi_val;
echo "\n";

echo "\n测试完成！\n";
