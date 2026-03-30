<?php
// Test 082: JsonSerializable
class JsonImpl implements JsonSerializable {
    public function __construct(
        public string $name,
        public int $value
    ) {}

    public function jsonSerialize(): array {
        return [
            'name' => $this->name,
            'value' => $this->value,
            'computed' => $this->name . '_' . $this->value,
        ];
    }
}

echo "=== JsonSerializable ===\n";
$obj = new JsonImpl('test', 42);
echo "json_encode: " . json_encode($obj) . "\n";

echo "\n=== Nested ===\n";
$nested = [
    'obj' => $obj,
    'arr' => [1, 2, 3],
];
echo "Nested json_encode: " . json_encode($nested) . "\n";

echo "\n=== Json error ===\n";
$invalid = '{"bad": json}';
json_decode($invalid);
echo "json_last_error: " . json_last_error() . "\n";
echo "json_last_error_msg: " . json_last_error_msg() . "\n";

echo "\n=== Json encode options ===\n";
$data = ['<tag>' => 'value', 'newline' => "line1\nline2"];
echo "Default: " . json_encode($data) . "\n";
echo "UNESCAPED_UNICODE: " . json_encode($data, JSON_UNESCAPED_UNICODE) . "\n";
echo "PRETTY: " . json_encode($data, JSON_PRETTY_PRINT) . "\n";

echo "\n=== Json decode ===\n";
$decoded = json_decode('{"a":1,"b":2}', true);
echo "Decoded: a=" . $decoded['a'] . ", b=" . $decoded['b'] . "\n";