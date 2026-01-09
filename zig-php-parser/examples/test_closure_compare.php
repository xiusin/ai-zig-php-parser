<?php
// Test: function returning closure vs closure returning closure

// Case 1: Function returning closure - works
function createMultiplierFn(int $factor) {
    return function(int $number) use ($factor) {
        return $number * $factor;
    };
}
$double_fn = createMultiplierFn(2);
echo "Function case: Double 5 = " . $double_fn(5) . "\n";

// Case 2: Closure returning closure - crashes
$multiplierClosure = function(int $factor) {
    return function(int $number) use ($factor) {
        return $number * $factor;
    };
};
$double_closure = $multiplierClosure(2);
echo "Closure case: Double 5 = " . $double_closure(5) . "\n";
?>
