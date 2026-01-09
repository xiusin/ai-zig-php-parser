<?php

function createCounter() {
    $count = 0;
    return function() use (&$count) {
        $count = $count + 1;
        return $count;
    };
}

$counter = createCounter();
echo "First call: " . $counter() . "\n";
echo "Second call: " . $counter() . "\n";
echo "Third call: " . $counter() . "\n";
