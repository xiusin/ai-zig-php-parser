<?php
// Closures
$multiplier = function(int $factor) {
    return function(int $number) use ($factor) {
        return $number * $factor;
    };
};

$double = $multiplier(2);
$triple = $multiplier(3);

echo "Double 5: " . $double(5) . "\n";
echo "Triple 5: " . $triple(5) . "\n";
?>
