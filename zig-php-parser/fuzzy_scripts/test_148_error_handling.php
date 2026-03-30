<?php
// Test 148: Error handling with @ operator
echo "=== @ operator ===\n";
$undefined = @$undefined_var;
echo "Undefined var with @: " . ($undefined ?? 'null') . "\n";

echo "\n=== Error suppression ===\n";
$arr = [];
$val = @$arr['missing']['key'];
echo "Missing array access with @: " . ($val ?? 'null') . "\n";

echo "\n=== Custom error handler ===\n";
function testErrorHandler(int $errno, string $errstr): bool {
    echo "Custom handler: $errstr\n";
    return true;
}

set_error_handler('testErrorHandler');
trigger_error("Test notice", E_USER_NOTICE);
restore_error_handler();
echo "Restored handler\n";