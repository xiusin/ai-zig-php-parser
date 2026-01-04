<?php
// Test call_user_func_array with undefined function
$result = call_user_func_array("undefined_function", [1, 2, 3]);
echo "Done\n";
