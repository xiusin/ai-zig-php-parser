<?php
// Test undefined variable in array_values
$arr = ["key" => $undefined_var];
$result = array_values($arr);
echo "Done\n";
