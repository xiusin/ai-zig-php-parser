<?php
function apply($value, $callback) {
    return $callback($value);
}

echo apply(5, function($x) { return $x * $x; }) . "\n";
echo apply("hello", "strlen") . "\n";

function doOperation($a, $b, $operation) {
    return $operation($a, $b);
}

$add = function($x, $y) { return $x + $y; };
echo doOperation(10, 20, $add) . "\n";
