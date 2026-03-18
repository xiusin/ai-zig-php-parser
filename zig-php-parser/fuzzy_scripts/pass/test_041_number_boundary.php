<?php
// 测试41: 数值边界与溢出
$maxInt = PHP_INT_MAX;
$minInt = PHP_INT_MIN;

echo "PHP_INT_MAX: $maxInt\n";
echo "PHP_INT_MIN: $minInt\n";

// 溢出测试
$overflow = $maxInt + 1;
echo "MAX + 1: $overflow\n";
echo "Type: " . gettype($overflow) . "\n";

$underflow = $minInt - 1;
echo "MIN - 1: $underflow\n";

// 浮点数精度
$a = 0.1;
$b = 0.2;
$c = 0.3;
echo "0.1 + 0.2 == 0.3: " . (($a + $b == $c) ? "true" : "false") . "\n";
echo "0.1 + 0.2: " . ($a + $b) . "\n";

// 科学计数法
$sci = 1.5e10;
echo "1.5e10: $sci\n";
echo "1.5e-5: " . 1.5e-5 . "\n";

// INF和NAN
$inf = 1.0 / 0.0;
$nan = 0.0 / 0.0;
echo "1.0/0.0: $inf\n";
echo "0.0/0.0: $nan\n";
echo "is_inf: " . (is_infinite($inf) ? "yes" : "no") . "\n";
echo "is_nan: " . (is_nan($nan) ? "yes" : "no") . "\n";
echo "is_finite: " . (is_finite(1.0) ? "yes" : "no") . "\n";

// 大数处理
$big = "9223372036854775808"; // 超过64位整数
echo "Big string number: $big\n";

// GMP扩展检查
if (extension_loaded("gmp")) {
    $gmp1 = gmp_init("12345678901234567890");
    $gmp2 = gmp_init("98765432109876543210");
    $sum = gmp_add($gmp1, $gmp2);
    echo "GMP sum: " . gmp_strval($sum) . "\n";
} else {
    echo "GMP extension not loaded\n";
}

// BCMath扩展检查
if (extension_loaded("bcmath")) {
    $bc1 = "12345678901234567890.12345";
    $bc2 = "98765432109876543210.54321";
    $sum = bcadd($bc1, $bc2, 5);
    echo "BCMath sum: $sum\n";
} else {
    echo "BCMath extension not loaded\n";
}
?>
