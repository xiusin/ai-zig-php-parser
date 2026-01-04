<?php
// Test undefined variable in array_map
$arr = [1, 2, 3];
$result = array_map(function($x) use ($undefined_var) {
    return $x + $undefined_var;
}, $arr);
echo "Done\n";
