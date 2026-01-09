<?php
class Counter {
    public $count = 0;
}

function increment($counter) {
    $counter->count++;
    return $counter;
}

$counter = new Counter();
$counter = increment($counter);
$counter = increment($counter);
$counter->count++;
echo "Count: " . $counter->count . "\n";
