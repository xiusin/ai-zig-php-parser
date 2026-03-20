<?php
// Test 138: Type casting between scalars
echo "=== Int casting ===\n";
echo "(int)true: " . (int)true . "\n";
echo "(int)false: " . (int)false . "\n";
echo "(int)3.14: " . (int)3.14 . "\n";
echo "(int)'123abc': " . (int)'123abc' . "\n";
echo "(int)'': " . (int)'' . "\n";

echo "\n=== Float casting ===\n";
echo "(float)'3.14': " . (float)'3.14' . "\n";
echo "(float)100: " . (float)100 . "\n";
echo "(float)true: " . (float)true . "\n";

echo "\n=== String casting ===\n";
echo "(string)123: " . (string)123 . "\n";
echo "(string)3.14: " . (string)3.14 . "\n";
echo "(string)true: " . (string)true . "\n";
echo "(string)false: " . (string)false . "\n";

echo "\n=== Bool casting ===\n";
echo "(bool)1: " . ((bool)1 ? 'true' : 'false') . "\n";
echo "(bool)0: " . ((bool)0 ? 'true' : 'false') . "\n";
echo "(bool)'': " . ((bool)'' ? 'true' : 'false') . "\n";
echo "(bool)'non-empty': " . ((bool)'non-empty' ? 'true' : 'false') . "\n";