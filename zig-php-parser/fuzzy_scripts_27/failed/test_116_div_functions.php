<?php
// Test 116: fdiv, fmod, intdiv
echo "=== fdiv ===\n";
echo "fdiv(10, 3): " . fdiv(10, 3) . "\n";
echo "fdiv(-10, 3): " . fdiv(-10, 3) . "\n";
echo "fdiv(10, -3): " . fdiv(10, -3) . "\n";
echo "fdiv(INF, 2): " . fdiv(INF, 2) . "\n";

echo "\n=== fmod ===\n";
echo "fmod(10.5, 3.2): " . fmod(10.5, 3.2) . "\n";
echo "fmod(7.5, 2.0): " . fmod(7.5, 2.0) . "\n";

echo "\n=== intdiv ===\n";
echo "intdiv(10, 3): " . intdiv(10, 3) . "\n";
echo "intdiv(-10, 3): " . intdiv(-10, 3) . "\n";
echo "intdiv(10, -3): " . intdiv(10, -3) . "\n";
echo "intdiv(-10, -3): " . intdiv(-10, -3) . "\n";

echo "\n=== Edge cases ===\n";
echo "intdiv(PHP_INT_MAX, 2): " . intdiv(PHP_INT_MAX, 2) . "\n";
echo "intdiv(PHP_INT_MIN, 2): " . intdiv(PHP_INT_MIN, 2) . "\n";