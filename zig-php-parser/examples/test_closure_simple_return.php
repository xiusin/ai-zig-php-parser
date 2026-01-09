<?php
// Simple closure returning closure - no captures
$createFn = function() {
    $inner = function() { return 100; };
    return $inner;
};
$fn = $createFn();
echo "Result: " . $fn() . "\n";
?>
