<?php
// Test file for line number tracking
echo "Line 3\n";
$undefined_var = $non_existent; // Line 4: undefined variable
echo "Line 5\n";
function test_func() {
    echo "Line 7\n";
    $another_undefined = $does_not_exist; // Line 8: undefined variable
}
test_func();
echo "Line 10\n";
