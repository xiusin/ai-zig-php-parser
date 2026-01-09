<?php
$items = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

$middle = array_slice($items, 3, 4);
echo "Middle (slice): " . implode(", ", $middle) . "\n";

$copy = $items;
array_splice($copy, 3, 4, [30, 40, 50]);
echo "After splice: " . implode(", ", $copy) . "\n";
