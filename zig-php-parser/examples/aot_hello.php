<?php
/**
 * AOT Compilation Example: Hello World
 * 
 * This is a simple example demonstrating basic AOT compilation features.
 * 
 * Features demonstrated:
 * - Basic echo output
 * - Variable declaration and assignment
 * - String interpolation
 * - Simple arithmetic operations
 * - String concatenation
 * 
 * Compile with:
 *   ./zig-out/bin/php-interpreter --compile examples/aot_hello.php
 * 
 * Compile with optimizations:
 *   ./zig-out/bin/php-interpreter --compile --optimize=release-fast examples/aot_hello.php
 * 
 * Run the compiled binary:
 *   ./aot_hello
 * 
 * Expected output:
 *   Hello from AOT-compiled PHP!
 *   Hello, World!
 *   Sum of 10 and 20 is 30
 *   Welcome to AOT PHP
 *   AOT compilation successful!
 */

// Basic output
echo "Hello from AOT-compiled PHP!\n";

// Variable declaration and string interpolation
$name = "World";
echo "Hello, {$name}!\n";

// Simple arithmetic operations
$a = 10;
$b = 20;
$sum = $a + $b;
echo "Sum of {$a} and {$b} is {$sum}\n";

// String concatenation using the . operator
$greeting = "Welcome to " . "AOT PHP";
echo $greeting . "\n";

// Final message
echo "AOT compilation successful!\n";
