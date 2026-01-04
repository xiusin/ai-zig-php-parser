<?php
// Test undefined variable in recursive function
function recursive($n) {
    if ($n <= 0) {
        return $undefined_var; // Undefined in base case
    }
    return recursive($n - 1);
}
recursive(5);
echo "Done\n";
