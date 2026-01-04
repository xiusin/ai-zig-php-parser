<?php
// Test undefined variable in switch statement
switch ($undefined_var) {
    case 1:
        echo "1\n";
        break;
    default:
        echo "default\n";
}
echo "Done\n";
