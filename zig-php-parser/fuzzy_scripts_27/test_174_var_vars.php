<?php
// Test 174: Variable variables with arrays
$base = 'item';
${$base} = 'direct';
${$base . '_1'} = 'suffix_1';
${$base . '_2'} = 'suffix_2';

echo "=== Variable variables ===\n";
echo "item: $item\n";
echo "item_1: $item_1\n";
echo "item_2: $item_2\n";