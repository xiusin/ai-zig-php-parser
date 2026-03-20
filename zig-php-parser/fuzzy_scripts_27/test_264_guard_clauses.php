<?php
function guard(bool $condition, string $message = 'Guard failed'): void {
    if (!$condition) {
        throw new RuntimeException($message);
    }
}

function requireNonNull(mixed $value, string $message = 'Value cannot be null'): mixed {
    if ($value === null) {
        throw new InvalidArgumentException($message);
    }
    return $value;
}

function requireNonEmpty(mixed $value, string $message = 'Value cannot be empty'): mixed {
    if (empty($value)) {
        throw new InvalidArgumentException($message);
    }
    return $value;
}

function assertType(mixed $value, string $expectedType): mixed {
    $actualType = gettype($value);
    if ($actualType !== $expectedType) {
        throw new TypeError("Expected $expectedType, got $actualType");
    }
    return $value;
}

try {
    guard(false, "Custom guard message");
} catch (RuntimeException $e) {
    echo $e->getMessage() . "\n";
}

try {
    requireNonNull(null);
} catch (InvalidArgumentException $e) {
    echo $e->getMessage() . "\n";
}

echo requireNonEmpty("hello") . "\n";

try {
    assertType("string", "int");
} catch (TypeError $e) {
    echo $e->getMessage() . "\n";
}
echo "OK\n";
