<?php
/**
 * AOT Compilation Example: Arrays
 * 
 * Demonstrates array operations in AOT-compiled PHP.
 * 
 * Features demonstrated:
 * - Indexed arrays (numeric keys)
 * - Associative arrays (string keys)
 * - Array element access
 * - Array push operation
 * - foreach loops with arrays
 * - for loops with count()
 * - Nested/multidimensional arrays
 * - Array iteration and accumulation
 * 
 * Compile with:
 *   ./zig-out/bin/php-interpreter --compile examples/aot_arrays.php
 * 
 * Run the compiled binary:
 *   ./aot_arrays
 * 
 * Expected output:
 *   Numbers: 1 2 3 4 5 
 *   Person: Alice, 30 years old, from New York
 *   Fruits: apple, banana, cherry, date
 *   Matrix diagonal: 1 5 9 
 *   Sum of numbers: 15
 */

// Simple indexed array
$numbers = [1, 2, 3, 4, 5];
echo "Numbers: ";
foreach ($numbers as $num) {
    echo $num . " ";
}
echo "\n";

// Associative array with string keys
$person = [
    "name" => "Alice",
    "age" => 30,
    "city" => "New York"
];

echo "Person: " . $person["name"] . ", " . $person["age"] . " years old, from " . $person["city"] . "\n";

// Array manipulation - push element
$fruits = ["apple", "banana", "cherry"];
$fruits[] = "date";  // Push element to end of array

echo "Fruits: ";
for ($i = 0; $i < count($fruits); $i++) {
    echo $fruits[$i];
    if ($i < count($fruits) - 1) {
        echo ", ";
    }
}
echo "\n";

// Nested/multidimensional array
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

// Array iteration with accumulation
$sum = 0;
foreach ($numbers as $n) {
    $sum = $sum + $n;
}
echo "Sum of numbers: " . $sum . "\n";
