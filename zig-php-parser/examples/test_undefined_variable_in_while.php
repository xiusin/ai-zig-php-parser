<?php
// Test undefined variable in while condition
while ($undefined_var) {
    echo "Loop\n";
    break;
}
echo "Done\n";
