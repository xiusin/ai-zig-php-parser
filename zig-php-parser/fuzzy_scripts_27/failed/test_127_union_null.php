<?php
// Test 127: Union types with null
class UnionNull {
    public int|string|null $prop;

    public function process(int|string|null $value): string {
        if ($value === null) return 'null';
        if (is_int($value)) return "int: $value";
        return "string: $value";
    }

    public function returnUnion(): int|array|null {
        return match(rand(0, 2)) {
            0 => 42,
            1 => ['array'],
            2 => null,
        };
    }
}

echo "=== Union with null ===\n";
$obj = new UnionNull();
$obj->prop = 123;
echo "Int prop: " . $obj->process($obj->prop) . "\n";

$obj->prop = 'string';
echo "String prop: " . $obj->process($obj->prop) . "\n";

$obj->prop = null;
echo "Null prop: " . $obj->process($obj->prop) . "\n";

echo "\n=== Return union with null ===\n";
for ($i = 0; $i < 3; $i++) {
    $result = $obj->returnUnion();
    echo "Returned: " . $obj->process($result) . "\n";
}