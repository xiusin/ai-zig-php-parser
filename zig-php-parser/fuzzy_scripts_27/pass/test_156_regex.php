<?php
// Test 156: preg_replace and preg_split
echo "=== preg_replace ===\n";
$text = "Hello123World456";
$replaced = preg_replace('/\d+/', '#', $text);
echo "Replaced digits: $replaced\n";

echo "\n=== preg_split ===\n";
$parts = preg_split('/\s+/', "one two three four");
echo "Split: " . implode('|', $parts) . "\n";

echo "\n=== preg_match ===\n";
preg_match('/\d+/', $text, $matches);
echo "Matches: " . json_encode($matches) . "\n";