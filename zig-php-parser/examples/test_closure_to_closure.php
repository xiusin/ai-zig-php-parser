<?php
// Closure that returns another closure
$createFn = function() {
    return function() { return 200; };
};
$innerFn = $createFn();
echo "Inner result: " . $innerFn() . "\n";
?>
