<?php

class Calculator {
    public function makeMultiplier($factor) {
        return fn($x) => $x * $factor;
    }
}

$calc = new Calculator();
$double = $calc->makeMultiplier(2);
echo "Double of 5: " . $double(5) . "\n";

$triple = $calc->makeMultiplier(3);
echo "Triple of 5: " . $triple(5) . "\n";

echo "Done\n";
