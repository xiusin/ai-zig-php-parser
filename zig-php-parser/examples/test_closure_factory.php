<?php
// Closure factory
function createMultiplier(int $factor) {
    return function(int $number) use ($factor) {
        return $number * $factor;
    };
}

$double = createMultiplier(2);
echo "Double 5: " . $double(5) . "\n";
?>
