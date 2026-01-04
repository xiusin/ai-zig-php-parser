<?php
// Array operations example

// Indexed arrays
$numbers = [1, 2, 3, 4, 5];
echo "Numbers: " . implode(", ", $numbers) . "\n";

// Associative arrays
$person = [
    "name" => "John Doe",
    "age" => 30,
    "city" => "New York"
];

echo "Person: {$person['name']}, Age: {$person['age']}, City: {$person['city']}\n";

// Array functions
$doubled = array_map(function($x) { return $x * 2; }, $numbers);
echo "Doubled: " . implode(", ", $doubled) . "\n";

$evens = array_filter($numbers, function($x) { return $x % 2 === 0; });
echo "Even numbers: " . implode(", ", $evens) . "\n";

$sum = array_reduce($numbers, function($carry, $item) { return $carry + $item; }, 0);
echo "Sum: {$sum}\n";

// Multi-dimensional arrays
$matrix = [
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9]
];

echo "Matrix:\n";
foreach ($matrix as $row) {
    echo implode(" ", $row) . "\n";
}

// Array manipulation
array_push($numbers, 6, 7);
echo "After push: " . implode(", ", $numbers) . "\n";

$last = array_pop($numbers);
echo "Popped: {$last}, Remaining: " . implode(", ", $numbers) . "\n";

// Array sorting
$unsorted = [3, 1, 4, 1, 5, 9, 2, 6];
sort($unsorted);
echo "Sorted: " . implode(", ", $unsorted) . "\n";
?>