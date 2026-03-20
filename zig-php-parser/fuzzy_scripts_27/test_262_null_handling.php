<?php
function nullCoalesce(mixed $a, mixed $b): mixed {
    return $a ?? $b;
}

function spaceship(mixed $a, mixed $b): int {
    return $a <=> $b;
}

function ifNull(mixed $value, mixed $default): mixed {
    return $value ?? $default;
}

function unless(mixed $value, callable $fn): mixed {
    return $value ?? $fn();
}

$result = nullCoalesce(null, 'default');
echo $result . "\n";

$result = spaceship(5, 3);
echo $result . "\n";

$result = ifNull(null, 100);
echo $result . "\n";

$result = unless(null, fn() => 200);
echo $result . "\n";

$result = unless("has value", fn() => "computed");
echo $result . "\n";
echo "OK\n";
