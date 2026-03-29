<?php
// Test 128: get_resource_id
$fh = fopen('php://memory', 'r+');
echo "=== get_resource_id ===\n";
echo "Resource ID: " . get_resource_id($fh) . "\n";
echo "Resource type: " . get_resource_type($fh) . "\n";
fclose($fh);

echo "\n=== Null/false resources ===\n";
$nullRes = null;
echo "get_resource_id on null: " . @get_resource_id($nullRes) . "\n";