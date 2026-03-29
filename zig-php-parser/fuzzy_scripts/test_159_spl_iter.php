<?php
// Test 159: Object iteration with SPL
$it = new ArrayIterator(['x' => 10, 'y' => 20, 'z' => 30]);
echo "=== ArrayIterator ===\n";
foreach ($it as $k => $v) {
    echo "  $k => $v\n";
}

echo "\n=== Iterator methods ===\n";
$it->rewind();
echo "After rewind: " . $it->current() . "\n";
$it->next();
echo "After next: " . $it->current() . "\n";