<?php
/**
 * AOT Compilation Example: Functions
 * 
 * Demonstrates function definitions and calls in AOT-compiled PHP.
 * 
 * Features demonstrated:
 * - Simple function definition and calling
 * - Functions with multiple parameters
 * - Recursive functions (Fibonacci)
 * - Functions with default parameter values
 * - Type declarations (string, int)
 * - Return statements
 * 
 * Compile with:
 *   ./zig-out/bin/php-interpreter --compile examples/aot_functions.php
 * 
 * Compile with optimizations (recommended for recursive functions):
 *   ./zig-out/bin/php-interpreter --compile --optimize=release-fast examples/aot_functions.php
 * 
 * Run the compiled binary:
 *   ./aot_functions
 * 
 * Expected output:
 *   Hello, AOT User!
 *   5 + 3 = 8
 *   Fibonacci(10) = 55
 *   2^8 = 256
 *   5^2 = 25
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
// Note: AOT compilation with optimizations makes recursive functions much faster
function fibonacci(int $n): int {
    if ($n <= 1) {
        return $n;
    }
    return fibonacci($n - 1) + fibonacci($n - 2);
}

// Function with default parameter value
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
echo "5^2 = " . power(5) . "\n";  // Uses default exponent of 2
