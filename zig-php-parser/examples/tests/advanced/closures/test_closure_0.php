<?php
function createCounter($start, $step) {
    $count = $start;
    return function() use (&$count, $step) {
        $count = $count + $step;
        return $count;
    };
}

$counter1 = createCounter(0, 1);
$counter2 = createCounter(10, 2);

echo "Counter1: " . $counter1() . "\n";
echo "Counter1: " . $counter1() . "\n";
echo "Counter1: " . $counter1() . "\n";

echo "Counter2: " . $counter2() . "\n";
echo "Counter2: " . $counter2() . "\n";
echo "Counter2: " . $counter2() . "\n";
?>