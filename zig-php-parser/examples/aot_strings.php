<?php
/**
 * AOT Compilation Example: String Operations
 * 
 * Demonstrates string manipulation in AOT-compiled PHP.
 * 
 * Features demonstrated:
 * - String concatenation with . operator
 * - String interpolation with {$var}
 * - strlen() - get string length
 * - strtoupper() - convert to uppercase
 * - strtolower() - convert to lowercase
 * - substr() - extract substring
 * - str_replace() - replace text in string
 * - Building strings in loops
 * - Multi-line strings
 * 
 * Compile with:
 *   ./zig-out/bin/php-interpreter --compile examples/aot_strings.php
 * 
 * Run the compiled binary:
 *   ./aot_strings
 * 
 * Expected output:
 *   Hello, World!
 *   Welcome to PHP version 8.5
 *   Length of 'AOT Compilation': 15
 *   Original: The quick brown fox jumps over the lazy dog
 *   Uppercase: THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG
 *   Lowercase: the quick brown fox jumps over the lazy dog
 *   Substring (4, 5): quick
 *   Replaced: The quick brown cat jumps over the lazy dog
 *   Built string: 1-2-3-4-5
 *   Multi-line:
 *   Line 1
 *   Line 2
 *   Line 3
 */

// String concatenation using the . operator
$first = "Hello";
$second = "World";
$greeting = $first . ", " . $second . "!";
echo $greeting . "\n";

// String interpolation using {$var} syntax
$name = "PHP";
$version = "8.5";
echo "Welcome to {$name} version {$version}\n";

// String length with strlen()
$text = "AOT Compilation";
echo "Length of '{$text}': " . strlen($text) . "\n";

// String case conversion functions
$sentence = "The quick brown fox jumps over the lazy dog";
echo "Original: " . $sentence . "\n";
echo "Uppercase: " . strtoupper($sentence) . "\n";
echo "Lowercase: " . strtolower($sentence) . "\n";

// Substring extraction with substr()
$word = substr($sentence, 4, 5);
echo "Substring (4, 5): " . $word . "\n";

// String replacement with str_replace()
$replaced = str_replace("fox", "cat", $sentence);
echo "Replaced: " . $replaced . "\n";

// Building strings in a loop
$result = "";
for ($i = 1; $i <= 5; $i++) {
    $result = $result . $i;
    if ($i < 5) {
        $result = $result . "-";
    }
}
echo "Built string: " . $result . "\n";

// Multi-line string
$multiline = "Line 1
Line 2
Line 3";
echo "Multi-line:\n" . $multiline . "\n";
