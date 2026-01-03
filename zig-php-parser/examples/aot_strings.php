<?php
/**
 * AOT Compilation Example: String Operations
 * 
 * Demonstrates string manipulation in AOT-compiled PHP.
 * 
 * Compile with:
 *   zig-php --compile examples/aot_strings.php
 */

// String concatenation
$first = "Hello";
$second = "World";
$greeting = $first . ", " . $second . "!";
echo $greeting . "\n";

// String interpolation
$name = "PHP";
$version = "8.5";
echo "Welcome to {$name} version {$version}\n";

// String length
$text = "AOT Compilation";
echo "Length of '{$text}': " . strlen($text) . "\n";

// String functions
$sentence = "The quick brown fox jumps over the lazy dog";
echo "Original: " . $sentence . "\n";
echo "Uppercase: " . strtoupper($sentence) . "\n";
echo "Lowercase: " . strtolower($sentence) . "\n";

// Substring
$word = substr($sentence, 4, 5);
echo "Substring (4, 5): " . $word . "\n";

// String replacement
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
