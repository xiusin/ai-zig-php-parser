<?php
function arrayChunk2(array $arr, int $size): array {
    return array_chunk($arr, $size);
}

function arrayColumn2(array $arr, int|string|null $column_key, int|string|null $index_key = null): array {
    return array_column($arr, $column_key, $index_key);
}

function arrayCombine2(array $keys, array $values): array {
    return array_combine($keys, $values);
}

function arrayIntersect2(array $arr1, array $arr2): array {
    return array_intersect($arr1, $arr2);
}

function arrayDiff2(array $arr1, array $arr2): array {
    return array_diff($arr1, $arr2);
}

$users = [
    ['id' => 1, 'name' => 'Alice'],
    ['id' => 2, 'name' => 'Bob'],
    ['id' => 3, 'name' => 'Charlie'],
];

print_r(arrayChunk2([1, 2, 3, 4, 5], 2));
print_r(arrayColumn2($users, 'name'));
print_r(arrayCombine2(['a', 'b', 'c'], [1, 2, 3]));
print_r(arrayIntersect2([1, 2, 3], [2, 3, 4]));
print_r(arrayDiff2([1, 2, 3], [2, 3, 4]));
echo "OK\n";
