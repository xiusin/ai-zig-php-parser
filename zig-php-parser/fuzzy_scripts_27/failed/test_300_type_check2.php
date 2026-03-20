<?php
function isNull2(mixed $value): bool {
    return is_null($value);
}

function isNumeric2(mixed $value): bool {
    return is_numeric($value);
}

function isCountable2(mixed $value): bool {
    return is_countable($value);
}

function isIterable2(mixed $value): bool {
    return is_iterable($value);
}

function isObject2(mixed $value): bool {
    return is_object($value);
}

function isResource2(mixed $value): bool {
    return is_resource($value);
}

function isScalar2(mixed $value): bool {
    return is_scalar($value);
}

function isCallable2(mixed $value): bool {
    return is_callable($value);
}

echo isNull2(null) ? 'true' : 'false' . "\n";
echo isNumeric2('123') ? 'true' : 'false' . "\n";
echo isCountable2([1, 2, 3]) ? 'true' : 'false' . "\n";
echo isIterable2([1, 2, 3]) ? 'true' : 'false' . "\n";
echo isObject2(new stdClass) ? 'true' : 'false' . "\n";
echo isScalar2('hello') ? 'true' : 'false' . "\n";
echo isCallable2('strlen') ? 'true' : 'false' . "\n";
echo "OK\n";
