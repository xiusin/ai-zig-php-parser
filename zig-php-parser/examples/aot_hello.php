<?php
/**
 * AOT Compilation Example: Hello World
 * 
 * This is a simple example demonstrating AOT compilation.
 * 
 * Compile with:
 *   zig-php --compile examples/aot_hello.php
 * 
 * Run the compiled binary:
 *   ./aot_hello
 */

echo "Hello from AOT-compiled PHP!\n";

$name = "World";
echo "Hello, {$name}!\n";

// Simple arithmetic
$a = 10;
$b = 20;
$sum = $a + $b;
echo "Sum of {$a} and {$b} is {$sum}\n";

// String operations
$greeting = "Welcome to " . "AOT PHP";
echo $greeting . "\n";

echo "AOT compilation successful!\n";
