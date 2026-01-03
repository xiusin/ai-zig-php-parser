<?php
/**
 * AOT Compilation Example: Functions
 * 
 * Demonstrates function definitions and calls in AOT-compiled PHP.
 * 
 * Compile with:
 *   zig-php --compile --optimize=release-fast examples/aot_functions.php
 */

// Simple function
function greet(string $name): string {
    return "Hello, " . $name . "!";
}

// Function with multiple parameters
function add(int $a, int $b): int {
    return $a + $b;
}

// Recursive function (Fibonacci)
function fibonacci(int $n): int {
    if ($n <= 1) {
        return $n;
    }
    return fibonacci($n - 1) + fibonacci($n - 2);
}

// Function with default parameter
function power(int $base, int $exp = 2): int {
    $result = 1;
    for ($i = 0; $i < $exp; $i++) {
        $result = $result * $base;
    }
    return $result;
}

// Test the functions
echo greet("AOT User") . "\n";
echo "5 + 3 = " . add(5, 3) . "\n";
echo "Fibonacci(10) = " . fibonacci(10) . "\n";
echo "2^8 = " . power(2, 8) . "\n";
echo "5^2 = " . power(5) . "\n";
