<?php
function boolVal2(mixed $value): bool {
    return (bool)$value;
}

function intVal2(mixed $value): int {
    return (int)$value;
}

function floatVal2(mixed $value): float {
    return (float)$value;
}

function strVal2(mixed $value): string {
    return (string)$value;
}

function getType2(mixed $value): string {
    return gettype($value);
}

function isArray2(mixed $value): bool {
    return is_array($value);
}

function isBool2(mixed $value): bool {
    return is_bool($value);
}

function isInt2(mixed $value): bool {
    return is_int($value);
}

function isFloat2(mixed $value): bool {
    return is_float($value);
}

function isString2(mixed $value): bool {
    return is_string($value);
}

echo getType2(123) . "\n";
echo getType2(3.14) . "\n";
echo getType2('hello') . "\n";
echo boolVal2(1) ? 'true' : 'false' . "\n";
echo intVal2(3.14) . "\n";
echo floatVal2('3.14') . "\n";
echo isArray2([]) ? 'true' : 'false' . "\n";
echo isInt2(42) ? 'true' : 'false' . "\n";
echo "OK\n";
