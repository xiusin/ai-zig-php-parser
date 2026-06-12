<?php
// 数学函数测试

// 基础数学运算
echo "abs(-5) = " . abs(-5) . "\n";
echo "ceil(4.3) = " . ceil(4.3) . "\n";
echo "floor(4.7) = " . floor(4.7) . "\n";
echo "round(4.5) = " . round(4.5) . "\n";
echo "round(4.4) = " . round(4.4) . "\n";

// 幂和对数
echo "pow(2, 10) = " . pow(2, 10) . "\n";
echo "2 ** 10 = " . (2 ** 10) . "\n";
echo "exp(1) = " . exp(1) . "\n";
echo "log(M_E) = " . log(M_E) . "\n";
echo "log10(100) = " . log10(100) . "\n";
echo "sqrt(16) = " . sqrt(16) . "\n";

// 三角函数
echo "sin(0) = " . sin(0) . "\n";
echo "cos(0) = " . cos(0) . "\n";
echo "tan(M_PI_4) = " . tan(M_PI_4) . "\n";
echo "asin(1) = " . asin(1) . "\n";
echo "acos(0) = " . acos(0) . "\n";
echo "atan(1) = " . atan(1) . "\n";

// 双曲函数
echo "sinh(0) = " . sinh(0) . "\n";
echo "cosh(0) = " . cosh(0) . "\n";
echo "tanh(0) = " . tanh(0) . "\n";

// 进制转换
echo "decbin(10) = " . decbin(10) . "\n";
echo "dechex(255) = " . dechex(255) . "\n";
echo "decoct(8) = " . decoct(8) . "\n";
echo "bindec('1010') = " . bindec('1010') . "\n";
echo "hexdec('FF') = " . hexdec('FF') . "\n";
echo "octdec('10') = " . octdec('10') . "\n";
echo "base_convert('FF', 16, 2) = " . base_convert('FF', 16, 2) . "\n";

// 最大最小值
echo "max(1, 5, 3) = " . max(1, 5, 3) . "\n";
echo "min(1, 5, 3) = " . min(1, 5, 3) . "\n";
echo "max([1, 2, 3, 4, 5]) = " . max([1, 2, 3, 4, 5]) . "\n";
echo "min([1, 2, 3, 4, 5]) = " . min([1, 2, 3, 4, 5]) . "\n";

// 随机数（固定种子模拟）
mt_srand(12345);
echo "mt_rand() = " . mt_rand() . "\n";
echo "mt_rand(1, 100) = " . mt_rand(1, 100) . "\n";

srand(12345);
echo "rand() = " . rand() . "\n";
echo "rand(1, 100) = " . rand(1, 100) . "\n";

// 取模和取整
echo "fmod(10.5, 3) = " . fmod(10.5, 3) . "\n";
echo "intdiv(10, 3) = " . intdiv(10, 3) . "\n";

// 符号函数
echo "is_finite(log(0)) = " . var_export(is_finite(log(0)), true) . "\n";
echo "is_infinite(log(0)) = " . var_export(is_infinite(log(0)), true) . "\n";
echo "is_nan(acos(2)) = " . var_export(is_nan(acos(2)), true) . "\n";

// 浮点数检查
echo "is_nan(NAN) = " . var_export(is_nan(NAN), true) . "\n";
echo "is_infinite(INF) = " . var_export(is_infinite(INF), true) . "\n";

// 格式化
echo "number_format(1234567.89, 2) = " . number_format(1234567.89, 2) . "\n";
echo "number_format(1234.5, 2, ',', ' ') = " . number_format(1234.5, 2, ',', ' ') . "\n";

// 数学常量
echo "M_PI = " . M_PI . "\n";
echo "M_E = " . M_E . "\n";
echo "M_SQRT2 = " . M_SQRT2 . "\n";

// 弧度角度转换
echo "deg2rad(180) = " . deg2rad(180) . "\n";
echo "rad2deg(M_PI) = " . rad2deg(M_PI) . "\n";

// 符号
echo "abs(-3.14) = " . abs(-3.14) . "\n";

// 进制转换格式化
echo "sprintf binary: " . sprintf("%b", 10) . "\n";
echo "sprintf hex: " . sprintf("%x", 255) . "\n";
echo "sprintf octal: " . sprintf("%o", 8) . "\n";

// 浮点精度
echo "round(1.555, 2) = " . round(1.555, 2) . "\n";
echo "round(1.555, 2, PHP_ROUND_HALF_UP) = " . round(1.555, 2, PHP_ROUND_HALF_UP) . "\n";
echo "round(1.555, 2, PHP_ROUND_HALF_DOWN) = " . round(1.555, 2, PHP_ROUND_HALF_DOWN) . "\n";
