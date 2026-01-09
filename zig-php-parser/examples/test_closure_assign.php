<?php
// Create a closure and assign it to another variable
$fn1 = function() { return 1; };
$fn2 = $fn1;
echo "Result: " . $fn2() . "\n";
?>
