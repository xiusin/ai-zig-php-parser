<?php
// Test 194: Type casting to bool
echo "=== Bool casting ===\n";
echo "(bool)1: " . ((bool)1 ? 'true' : 'false') . "\n";
echo "(bool)0: " . ((bool)0 ? 'true' : 'false') . "\n";
echo "(bool)'': " . ((bool)'' ? 'true' : 'false') . "\n";
echo "(bool)'nonempty': " . ((bool)'nonempty' ? 'true' : 'false') . "\n";