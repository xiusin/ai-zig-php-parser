<?php
// Test 173: Error suppression and reporting
echo "=== Error suppression ===\n";
$val = @$undefined_variable;
echo "Suppressed: " . ($val ?? 'null') . "\n";

echo "\n=== Division by zero ===\n";
$result = @10 / 0;
echo "10/0: $result\n";