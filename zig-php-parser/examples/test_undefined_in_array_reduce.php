<?php
// Test undefined variable in array_reduce
$arr = [1, 2, 3];
$result = array_reduce($arr, function($carry, $item) use ($undefined_var) {
    return $carry + $item + $undefined_var;
}, 0);
echo "Done\n";
