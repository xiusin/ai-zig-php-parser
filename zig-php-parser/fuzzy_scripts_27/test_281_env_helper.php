<?php
function parseenv(string $key, mixed $default = null): mixed {
    $value = getenv($key);
    if ($value === false) return $default;

    if (strtolower($value) === 'true') return true;
    if (strtolower($value) === 'false') return false;
    if (strtolower($value) === 'null') return null;
    if (is_numeric($value)) return str_contains($value, '.') ? (float)$value : (int)$value;

    return $value;
}

$_SERVER['TEST_VAR'] = '123';
$_ENV['TEST_DB'] = 'mysql:host=localhost';

echo parseenv('TEST_VAR', 0) . "\n";
echo parseenv('TEST_DB', '') . "\n";
echo parseenv('MISSING', 'default') . "\n";
echo "OK\n";
