<?php
// Test 121: WeakMap (PHP 8)
class WeakMapTarget {}

echo "=== WeakMap basic ===\n";
$map = new WeakMap();

$obj1 = new WeakMapTarget();
$obj2 = new WeakMapTarget();

$map[$obj1] = ['value' => 'first'];
$map[$obj2] = ['value' => 'second'];

echo "WeakMap count: " . count($map) . "\n";
echo "obj1 in map: " . (isset($map[$obj1]) ? 'yes' : 'no') . "\n";
echo "obj1 value: " . ($map[$obj1]['value'] ?? 'null') . "\n";

echo "\n=== Iterate WeakMap ===\n";
foreach ($map as $obj => $value) {
    echo "Object: " . get_class($obj) . ", value: " . $value['value'] . "\n";
}

echo "\n=== Weak reference ===\n";
$ref = WeakReference::create($obj1);
echo "Original ref get: " . ($ref->get()?->data ?? 'no data') . "\n";

unset($obj1);
echo "After unset obj1, ref get: " . ($ref->get() ?? 'null') . "\n";
echo "WeakMap count after GC: " . count($map) . "\n";