<?php
// Test 171: Null coalescing operator
$a = null;
$b = "default_b";
$c = "value_c";

echo "=== Null coalescing ===\n";
echo "null ?? 'fallback': " . ($a ?? 'fallback') . "\n";
echo "'value' ?? 'fallback': " . ($c ?? 'fallback') . "\n";
echo "\$a ?? \$b ?? 'fallback': " . ($a ?? $b ?? 'fallback') . "\n";

echo "\n=== With arrays ===\n";
$arr = ['key' => null];
echo "arr['key'] ?? 'missing': " . ($arr['key'] ?? 'missing') . "\n";
echo "arr['missing'] ?? 'default': " . ($arr['missing'] ?? 'default') . "\n";