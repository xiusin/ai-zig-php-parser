<?php
// Test 125: Mixed type declaration
class MixedType {
    public mixed $mixedProp;

    public function process(mixed $value): string {
        return match(true) {
            is_int($value) => "int: $value",
            is_string($value) => "string: $value",
            is_array($value) => "array with " . count($value) . " items",
            is_bool($value) => "bool: " . ($value ? 'true' : 'false'),
            is_null($value) => "null",
            is_float($value) => "float: $value",
            is_object($value) => "object: " . get_class($value),
            default => "unknown type",
        };
    }

    public function returnMixed(): mixed {
        return match(rand(0, 5)) {
            0 => null,
            1 => 42,
            2 => 'string',
            3 => [1, 2, 3],
            4 => true,
            5 => new stdClass(),
        };
    }
}

echo "=== Mixed type ===\n";
$obj = new MixedType();
$obj->mixedProp = 'string value';
echo "String: " . $obj->process($obj->mixedProp) . "\n";

$obj->mixedProp = 123;
echo "Int: " . $obj->process($obj->mixedProp) . "\n";

$obj->mixedProp = ['a', 'b', 'c'];
echo "Array: " . $obj->process($obj->mixedProp) . "\n";

$obj->mixedProp = null;
echo "Null: " . $obj->process($obj->mixedProp) . "\n";

echo "\n=== Return mixed ===\n";
$obj->mixedProp = $obj->returnMixed();
echo "Mixed returned: " . $obj->process($obj->mixedProp) . "\n";