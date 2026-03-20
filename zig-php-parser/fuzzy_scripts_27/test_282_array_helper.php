<?php
function arrayGet(array $arr, string $key, mixed $default = null): mixed {
    return $arr[$key] ?? $default;
}

function arraySet(array &$arr, string $key, mixed $value): void {
    $arr[$key] = $value;
}

function arrayHas(array $arr, string $key): bool {
    return isset($arr[$key]);
}

function arrayForget(array &$arr, string $key): void {
    unset($arr[$key]);
}

function arrayPull(array &$arr, string $key, mixed $default = null): mixed {
    $value = arrayGet($arr, $key, $default);
    arrayForget($arr, $key);
    return $value;
}

$arr = ['name' => 'Alice', 'age' => 30, 'city' => 'NYC'];
echo arrayGet($arr, 'name', 'Unknown') . "\n";
echo arrayPull($arr, 'city', 'N/A') . "\n";
echo arrayHas($arr, 'city') ? 'true' : 'false' . "\n";
echo count($arr) . "\n";
echo "OK\n";
