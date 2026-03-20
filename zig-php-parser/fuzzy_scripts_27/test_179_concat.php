<?php
// Test 179: String concatenation
$a = "Hello";
$b = " ";
$c = "World";

echo "=== String concatenation ===\n";
echo "Concat: " . $a . $b . $c . "\n";
echo "With dots: $a.$b.$c\n";
echo "Assignment: " . ($a .= $b .= $c) . "\n";