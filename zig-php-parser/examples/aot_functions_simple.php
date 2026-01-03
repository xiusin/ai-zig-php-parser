<?php
/**
 * AOT Compilation Example: Simple Functions
 * 
 * Demonstrates basic function definitions and calls in AOT-compiled PHP.
 */

// Simple function with type declarations
function greet(string $name): string {
    return "Hello, " . $name . "!";
}

// Function with multiple parameters
function add(int $a, int $b): int {
    return $a + $b;
}

// Recursive function: Fibonacci sequence
function fibonacci(int $n): int {
    if ($n <= 1) {
        return $n;
    }
    return fibonacci($n - 1) + fibonacci($n - 2);
}

// Test the functions
echo greet("AOT User") . "\n";
echo "5 + 3 = " . add(5, 3) . "\n";
echo "Fibonacci(10) = " . fibonacci(10) . "\n";
