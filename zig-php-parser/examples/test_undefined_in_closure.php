<?php
// Test undefined variable in closure
$closure = function() use ($undefined_var) {
    echo $undefined_var . "\n";
};
$closure();
echo "Done\n";
