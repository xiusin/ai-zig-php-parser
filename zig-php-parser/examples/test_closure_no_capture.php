<?php
// Closure returning closure - no captures at all
$create = function() {
    return function() { return 77; };
};
$fn = $create();
echo "fn(): " . $fn() . "\n";
?>
