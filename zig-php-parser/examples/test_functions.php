<?php
// Basic function
function greet(string $name, string $greeting = "Hello"): string {
    return "{$greeting}, {$name}!";
}

echo greet("World") . "\n";
echo greet("Alice", "Hi") . "\n";

// Function with variable arguments
function sum(...$numbers): int {
    return array_sum($numbers);
}

echo "Sum: " . sum(1, 2, 3, 4, 5) . "\n";
?>
