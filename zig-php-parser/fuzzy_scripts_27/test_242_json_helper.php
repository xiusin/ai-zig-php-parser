<?php
function isValidJson(string $str): bool {
    json_decode($str);
    return json_last_error() === JSON_ERROR_NONE;
}

function tryJsonEncode(mixed $value, bool $pretty = false): string|null {
    try {
        if ($pretty) {
            return json_encode($value, JSON_PRETTY_PRINT);
        }
        return json_encode($value);
    } catch (Exception $e) {
        return null;
    }
}

function safeJsonDecode(string $str, bool $assoc = true): mixed {
    json_decode($str, $assoc);
    if (json_last_error() !== JSON_ERROR_NONE) {
        return null;
    }
    return json_decode($str, $assoc);
}

$valid = '{"name": "John", "age": 30, "active": true}';
$invalid = '{"name": "John", "age": }';

echo isValidJson($valid) ? 'true' : 'false' . "\n";
echo isValidJson($invalid) ? 'true' : 'false' . "\n";

$decoded = safeJsonDecode($valid);
echo $decoded['name'] . "\n";

$encoded = tryJsonEncode(['status' => 'ok', 'count' => 42]);
echo $encoded . "\n";
echo "OK\n";
