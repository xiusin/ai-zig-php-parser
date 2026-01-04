<?php
/**
 * AOT Compilation Example: Arrays
 * 
 * Demonstrates array operations in AOT-compiled PHP.
 * 
 * Compile with:
 *   zig-php --compile examples/aot_arrays.php
 */

// Simple array
$numbers = [1, 2, 3, 4, 5];
echo "Numbers: ";
foreach ($numbers as $num) {
    echo $num . " ";
}
echo "\n";

// Associative array
$person = [
    "name" => "Alice",
    "age" => 30,
    "city" => "New York"
];

echo "Person: " . $person["name"] . ", " . $person["age"] . " years old, from " . $person["city"] . "\n";

// Array manipulation
$fruits = ["apple", "banana", "cherry"];
$fruits[] = "date";  // Push element

echo "Fruits: ";
for ($i = 0; $i < count($fruits); $i++) {
    echo $fruits[$i];
    if ($i < count($fruits) - 1) {
        echo ", ";
    }
}
echo "\n";

// Nested array
$matrix = [
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9]
];

echo "Matrix diagonal: ";
for ($i = 0; $i < 3; $i++) {
    echo $matrix[$i][$i] . " ";
}
echo "\n";

// Array sum
$sum = 0;
foreach ($numbers as $n) {
    $sum = $sum + $n;
}
echo "Sum of numbers: " . $sum . "\n";
