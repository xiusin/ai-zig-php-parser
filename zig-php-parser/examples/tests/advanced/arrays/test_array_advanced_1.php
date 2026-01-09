<?php
$original = array(1, 2, 3, 4, 5);
$reference = &$original;
$copy = $original;

echo "Original: " . implode(", ", $original) . "\n";
echo "Reference: " . implode(", ", $reference) . "\n";
echo "Copy: " . implode(", ", $copy) . "\n";

$reference[0] = 100;
echo "\nAfter modifying reference[0] to 100:\n";
echo "Original: " . implode(", ", $original) . "\n";
echo "Reference: " . implode(", ", $reference) . "\n";
echo "Copy: " . implode(", ", $copy) . "\n";
?>