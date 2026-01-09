<?php
$numbers = range(1, 20);

// Filter even numbers
$evens = array_filter($numbers, function($n) {
    return $n % 2 == 0;
});

// Map to square
$squares = array_map(function($n) {
    return $n * $n;
}, $evens);

echo "Original: " . implode(", ", $numbers) . "\n";
echo "Evens: " . implode(", ", $evens) . "\n";
echo "Squares: " . implode(", ", $squares) . "\n";
