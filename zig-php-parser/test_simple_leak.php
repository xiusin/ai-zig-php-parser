<?php
// Simple test to check for memory leaks

echo "Test 1: Simple echo\n";
echo "Test 2: Array operations\n";
$arr = [1, 2, 3];
foreach ($arr as $v) {
    echo $v . "\n";
}
echo "Done\n";
