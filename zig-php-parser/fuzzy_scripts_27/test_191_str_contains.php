<?php
// Test 191: str_contains, str_starts_with, str_ends_with
$str = "Hello World";

echo "=== String functions ===\n";
echo "str_contains World: " . (str_contains($str, 'World') ? 'true' : 'false') . "\n";
echo "str_starts_with Hello: " . (str_starts_with($str, 'Hello') ? 'true' : 'false') . "\n";
echo "str_ends_with World: " . (str_ends_with($str, 'World') ? 'true' : 'false') . "\n";