<?php
// Test 154: Mixed array operations
$a = [1, 2, 3];
$b = ['a', 'b', 'c'];
$c = array_merge($a, $b);
echo "=== Array merge ===\n";
echo "array_merge: " . json_encode($c) . "\n";

echo "\n=== Array chunk ===\n";
$chunked = array_chunk([1, 2, 3, 4, 5], 2);
echo "Chunked: " . json_encode($chunked) . "\n";

echo "\n=== Array pad ===\n";
$padded = array_pad([1, 2], 5, 0);
echo "Padded: " . json_encode($padded) . "\n";