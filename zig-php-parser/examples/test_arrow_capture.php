<?php

function makeMultiplier($factor) {
    return fn($x) => $x * $factor;
}

$double = makeMultiplier(2);
echo "Double of 5: " . $double(5) . "\n";

$triple = makeMultiplier(3);
echo "Triple of 5: " . $triple(5) . "\n";

echo "Done\n";