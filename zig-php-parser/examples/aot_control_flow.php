<?php
/**
 * AOT Compilation Example: Control Flow
 * 
 * Demonstrates control flow structures in AOT-compiled PHP.
 * 
 * Features demonstrated:
 * - if/else/elseif statements
 * - while loops
 * - for loops
 * - foreach loops
 * - break and continue statements
 * - Nested control structures
 * - Comparison operators
 * - Logical operators
 * 
 * Compile with:
 *   ./zig-out/bin/php-interpreter --compile examples/aot_control_flow.php
 * 
 * Run the compiled binary:
 *   ./aot_control_flow
 * 
 * Expected output:
 *   === If/Else Demo ===
 *   x is positive
 *   Grade: B
 *   
 *   === While Loop Demo ===
 *   Countdown: 5 4 3 2 1 
 *   
 *   === For Loop Demo ===
 *   Squares: 1 4 9 16 25 
 *   
 *   === Foreach Loop Demo ===
 *   Colors: red green blue 
 *   
 *   === Break Demo ===
 *   Found 5 at index 4
 *   
 *   === Continue Demo ===
 *   Odd numbers: 1 3 5 7 9 
 *   
 *   === Nested Loops Demo ===
 *   1x1=1 1x2=2 1x3=3 
 *   2x1=2 2x2=4 2x3=6 
 *   3x1=3 3x2=6 3x3=9 
 */

echo "=== If/Else Demo ===\n";

// Simple if/else
$x = 10;
if ($x > 0) {
    echo "x is positive\n";
} else {
    echo "x is not positive\n";
}

// if/elseif/else chain
$score = 85;
if ($score >= 90) {
    echo "Grade: A\n";
} elseif ($score >= 80) {
    echo "Grade: B\n";
} elseif ($score >= 70) {
    echo "Grade: C\n";
} else {
    echo "Grade: F\n";
}

echo "\n=== While Loop Demo ===\n";

// While loop - countdown
$count = 5;
echo "Countdown: ";
while ($count > 0) {
    echo $count . " ";
    $count = $count - 1;
}
echo "\n";

echo "\n=== For Loop Demo ===\n";

// For loop - print squares
echo "Squares: ";
for ($i = 1; $i <= 5; $i++) {
    echo ($i * $i) . " ";
}
echo "\n";

echo "\n=== Foreach Loop Demo ===\n";

// Foreach loop - iterate over array
$colors = ["red", "green", "blue"];
echo "Colors: ";
foreach ($colors as $color) {
    echo $color . " ";
}
echo "\n";

echo "\n=== Break Demo ===\n";

// Break statement - exit loop early
$numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
$target = 5;
$found_index = -1;

for ($i = 0; $i < count($numbers); $i++) {
    if ($numbers[$i] == $target) {
        $found_index = $i;
        break;  // Exit loop when found
    }
}

if ($found_index >= 0) {
    echo "Found {$target} at index {$found_index}\n";
} else {
    echo "Not found\n";
}

echo "\n=== Continue Demo ===\n";

// Continue statement - skip even numbers
echo "Odd numbers: ";
for ($i = 1; $i <= 10; $i++) {
    if ($i % 2 == 0) {
        continue;  // Skip even numbers
    }
    echo $i . " ";
}
echo "\n";

echo "\n=== Nested Loops Demo ===\n";

// Nested loops - multiplication table
for ($i = 1; $i <= 3; $i++) {
    for ($j = 1; $j <= 3; $j++) {
        echo $i . "x" . $j . "=" . ($i * $j) . " ";
    }
    echo "\n";
}
