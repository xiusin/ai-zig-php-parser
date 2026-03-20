<?php
// Test 164: Function default arguments
function defaults(
    string $a = 'default_a',
    int $b = 10,
    bool $c = true,
    array $d = []
): string {
    return "a=$a, b=$b, c=" . ($c ? 'true' : 'false') . ", d_count=" . count($d);
}

echo "=== Default arguments ===\n";
echo defaults() . "\n";
echo defaults('custom') . "\n";
echo defaults('custom', 20) . "\n";
echo defaults('custom', 20, false) . "\n";
echo defaults(d: ['x' => 1]) . "\n";