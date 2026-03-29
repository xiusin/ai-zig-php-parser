<?php
// Test 142: Random functions and seeding
echo "=== Random functions ===\n";
echo "rand(1, 100): " . rand(1, 100) . "\n";
echo "mt_rand(1, 100): " . mt_rand(1, 100) . "\n";
echo "random_int(1, 100): " . random_int(1, 100) . "\n";

echo "\n=== Random bytes ===\n";
$bytes = random_bytes(8);
echo "random_bytes(8) hex: " . bin2hex($bytes) . "\n";

echo "\n=== Seed ===\n";
mt_srand(12345);
$val1 = mt_rand();
mt_srand(12345);
$val2 = mt_rand();
echo "Seeded rand1: $val1\n";
echo "Seeded rand2: $val2\n";
echo "Same seed same value: " . ($val1 === $val2 ? 'yes' : 'no') . "\n";