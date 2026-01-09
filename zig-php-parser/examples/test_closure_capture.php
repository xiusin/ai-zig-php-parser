<?php
// Closure with variable capture (value capture)
$factor = 3;
$multiplier = function(int $number) use ($factor) {
    return $number * $factor;
};

echo "5 * factor(3): " . $multiplier(5) . "\n";
?>
