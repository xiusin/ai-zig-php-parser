<?php
// Test undefined variable in array merge
$arr1 = [1, 2, 3];
$arr2 = [$undefined_var, 4, 5];
$result = array_merge($arr1, $arr2);
echo "Done\n";
