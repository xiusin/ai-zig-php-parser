<?php
// Test 114: str_contains, str_starts_with, str_ends_with (PHP 8+)
$haystack = "Hello World";

echo "=== str_contains ===\n";
echo "str_contains(\$haystack, 'World'): " . (str_contains($haystack, 'World') ? 'true' : 'false') . "\n";
echo "str_contains(\$haystack, 'world'): " . (str_contains($haystack, 'world') ? 'true' : 'false') . "\n";
echo "str_contains(\$haystack, 'Hello'): " . (str_contains($haystack, 'Hello') ? 'true' : 'false') . "\n";
echo "str_contains(\$haystack, 'xyz'): " . (str_contains($haystack, 'xyz') ? 'true' : 'false') . "\n";

echo "\n=== str_starts_with ===\n";
echo "str_starts_with(\$haystack, 'Hello'): " . (str_starts_with($haystack, 'Hello') ? 'true' : 'false') . "\n";
echo "str_starts_with(\$haystack, 'World'): " . (str_starts_with($haystack, 'World') ? 'true' : 'false') . "\n";
echo "str_starts_with(\$haystack, ''): " . (str_starts_with($haystack, '') ? 'true' : 'false') . "\n";

echo "\n=== str_ends_with ===\n";
echo "str_ends_with(\$haystack, 'World'): " . (str_ends_with($haystack, 'World') ? 'true' : 'false') . "\n";
echo "str_ends_with(\$haystack, 'Hello'): " . (str_ends_with($haystack, 'Hello') ? 'true' : 'false') . "\n";
echo "str_ends_with(\$haystack, ''): " . (str_ends_with($haystack, '') ? 'true' : 'false') . "\n";