<?php
// Test 132: Object storage and comparison
class StorageObj {
    public function __construct(public int $value) {}
}

$a = new StorageObj(1);
$b = new StorageObj(1);
$c = $a;

echo "=== Object identity ===\n";
echo "\$a === \$b: " . ($a === $b ? 'true' : 'false') . "\n";
echo "\$a === \$c: " . ($a === $c ? 'true' : 'false') . "\n";
echo "\$a == \$b: " . ($a == $b ? 'true' : 'false') . "\n";

echo "\n=== Object as array key ===\n";
$arr = [];
$arr[$a] = 'a_value';
$arr[$b] = 'b_value';
echo "Array count: " . count($arr) . "\n";

echo "\n=== Object serialization ===\n";
$serialized = serialize($a);
echo "Serialized length: " . strlen($serialized) . "\n";