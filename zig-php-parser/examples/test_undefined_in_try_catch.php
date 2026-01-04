<?php
// Test undefined variable in try-catch block
try {
    echo $undefined_var;
} catch (Exception $e) {
    echo "Caught exception\n";
}
echo "Done\n";
