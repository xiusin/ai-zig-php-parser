<?php
// Test undefined variable in return statement
function test() {
    return $undefined_var;
}
test();
echo "Done\n";
