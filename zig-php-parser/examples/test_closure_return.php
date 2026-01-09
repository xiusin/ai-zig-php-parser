<?php
// Closure returning closure
$multiplier = function(int $factor) {
    return function(int $number) use ($factor) {
        return $number * $factor;
    };
};

$double = $multiplier(2);
echo "Double 5: " . $double(5) . "\n";
?>
