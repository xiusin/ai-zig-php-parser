<?php
// Test 108: Nullsafe operator ?->
class NullsafeTarget {
    public string $value = 'target_value';
    public ?Child $child = null;
}

class Child {
    public string $name = 'child';
    public ?Leaf $leaf = null;
}

class Leaf {
    public string $data = 'leaf_data';
}

echo "=== Nullsafe operator ===\n";
$obj = new NullsafeTarget();
$obj->child = new Child();
$obj->child->leaf = new Leaf();

echo "obj?->value: " . ($obj?->value ?? 'null') . "\n";
echo "obj?->child?->name: " . ($obj?->child?->name ?? 'null') . "\n";
echo "obj?->child?->leaf?->data: " . ($obj?->child?->leaf?->data ?? 'null') . "\n";

echo "\n=== Nullsafe with null ===\n";
$nullObj = null;
echo "null?->value: " . ($nullObj?->value ?? 'null_safe') . "\n";
echo "null?->child?->name: " . ($nullObj?->child?->name ?? 'null_safe') . "\n";

echo "\n=== Nullsafe chain ===\n";
$obj->child->leaf = null;
echo "After leaf=null, obj?->child?->leaf?->data: " . ($obj?->child?->leaf?->data ?? 'null_after') . "\n";