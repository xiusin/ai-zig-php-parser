<?php
// Test undefined variable in array_filter
$arr = [1, 2, 3, 4, 5];
$result = array_filter($arr, function($x) use ($undefined_var) {
    return $x > $undefined_var;
});
echo "Done\n";
