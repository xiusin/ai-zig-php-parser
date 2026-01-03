<?php
// Test function parameters and scoping
function add($a, $b = 10) {
    $result = $a + $b;
    return $result;
}

$val = 5;
echo "Global val before: " . $val . "\n";
echo "Function call add(5): " . add(5) . "\n"; // Should be 15
echo "Function call add(5, 20): " . add(5, 20) . "\n"; // Should be 25
echo "Global val after: " . $val . "\n"; // Should still be 5

// Test nested calls
function square($n) {
    return $a * $a; // Note: $a is not defined here, should throw error if we don't fix it
}

// Fixed version using parameters
function square_fixed($n) {
    return $n * $n;
}

echo "Square of 4: " . square_fixed(4) . "\n";
?>
