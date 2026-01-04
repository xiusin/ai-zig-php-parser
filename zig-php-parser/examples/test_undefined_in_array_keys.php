<?php
// Test undefined variable in array_keys
$arr = [$undefined_var => "value"];
$result = array_keys($arr);
echo "Done\n";