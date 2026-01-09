<?php
function createMultiplier($factor) {
    return function($value) use ($factor) {
        return $value * $factor;
    };
}

$double = createMultiplier(2);
$triple = createMultiplier(3);

echo $double(5) . "\n";
echo $triple(5) . "\n";
