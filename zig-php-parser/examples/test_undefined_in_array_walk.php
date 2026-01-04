<?php
// Test undefined variable in array_walk
$arr = [1, 2, 3];
array_walk($arr, function(&$item, $key) use ($undefined_var) {
    $item = $item + $undefined_var;
});
echo "Done\n";
