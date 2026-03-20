<?php
// Test 085: Math functions
echo "=== Basic math ===\n";
echo "abs(-10): " . abs(-10) . "\n";
echo "round(3.5): " . round(3.5) . "\n";
echo "floor(3.9): " . floor(3.9) . "\n";
echo "ceil(3.1): " . ceil(3.1) . "\n";

echo "\n=== Power/Roots ===\n";
echo "pow(2, 10): " . pow(2, 10) . "\n";
echo "sqrt(16): " . sqrt(16) . "\n";
echo "exp(1): " . exp(1) . "\n";
echo "log(exp(1)): " . log(exp(1)) . "\n";

echo "\n=== Trig ===\n";
echo "sin(pi/2): " . sin(M_PI / 2) . "\n";
echo "cos(0): " . cos(0) . "\n";
echo "tan(pi/4): " . tan(M_PI / 4) . "\n";
echo "hypot(3, 4): " . hypot(3, 4) . "\n";

echo "\n=== Min/Max ===\n";
echo "min(1, 3, 2): " . min(1, 3, 2) . "\n";
echo "max(1, 3, 2): " . max(1, 3, 2) . "\n";
echo "min([3, 1, 2]): " . min([3, 1, 2]) . "\n";
echo "max([3, 1, 2]): " . max([3, 1, 2]) . "\n";

echo "\n=== Base conversion ===\n";
echo "base_convert('FF', 16, 10): " . base_convert('FF', 16, 10) . "\n";
echo "base_convert('1010', 2, 16): " . base_convert('1010', 2, 16) . "\n";

echo "\n=== Constants ===\n";
echo "M_PI: " . M_PI . "\n";
echo "M_E: " . M_E . "\n";
echo "PHP_INT_MAX: " . PHP_INT_MAX . "\n";
echo "PHP_INT_MIN: " . PHP_INT_MIN . "\n";