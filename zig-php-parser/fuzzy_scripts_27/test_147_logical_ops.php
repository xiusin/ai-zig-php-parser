<?php
// Test 147: Logical operators
$a = true;
$b = false;
$c = "non-empty";
$d = "";

echo "=== Logical operators ===\n";
echo "true && false: " . ((true && false) ? 'true' : 'false') . "\n";
echo "true || false: " . ((true || false) ? 'true' : 'false') . "\n";
echo "!false: " . ((!false) ? 'true' : 'false') . "\n";
echo "true and false: " . ((true and false) ? 'true' : 'false') . "\n";
echo "true or false: " . ((true or false) ? 'true' : 'false') . "\n";
echo "false xor true: " . ((false xor true) ? 'true' : 'false') . "\n";

echo "\n=== Short-circuit ===\n";
function sideEffect(): bool {
    echo "sideEffect called\n";
    return true;
}

false && sideEffect();
true || sideEffect();
echo "Short-circuit works\n";

echo "\n=== String logical ===\n";
echo "non-empty && true: " . (($c && true) ? 'true' : 'false') . "\n";
echo "empty || 'fallback': " . ($d ?: 'fallback') . "\n";