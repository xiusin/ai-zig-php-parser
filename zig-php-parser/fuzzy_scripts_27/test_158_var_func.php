<?php
// Test 158: Variable function names
function hello(): string {
    return "Hello";
}

function world(): string {
    return "World";
}

echo "=== Variable function ===\n";
$fn = 'hello';
echo "$fn(): " . $fn() . "\n";

$fn = 'world';
echo "$fn(): " . $fn() . "\n";