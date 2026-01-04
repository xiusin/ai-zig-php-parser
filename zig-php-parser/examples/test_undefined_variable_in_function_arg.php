<?php
// Test undefined variable as function argument
function test($a) {
    echo $a . "\n";
}
test($undefined_var);
echo "Done\n";
