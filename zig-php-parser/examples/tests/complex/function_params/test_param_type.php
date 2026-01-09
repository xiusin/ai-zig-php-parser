<?php
function add(int $a, int $b): int {
    return $a + $b;
}

function concat(string $a, string $b): string {
    return $a . $b;
}

function double(array $arr): array {
    return array_map(function($x) { return $x * 2; }, $arr);
}

echo add(1, 2) . "\n";
echo concat("Hello", "World") . "\n";
print_r(double([1, 2, 3]));
