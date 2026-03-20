<?php
function deepMerge(array $a, array $b): array {
    foreach ($b as $key => $value) {
        if (is_array($value) && isset($a[$key]) && is_array($a[$key])) {
            $a[$key] = deepMerge($a[$key], $value);
        } else {
            $a[$key] = $value;
        }
    }
    return $a;
}

function arrayDiffDeep(array $a, array $b): array {
    $diff = [];

    foreach ($a as $key => $value) {
        if (!array_key_exists($key, $b)) {
            $diff[$key] = $value;
        } elseif (is_array($value) && is_array($b[$key])) {
            $subDiff = arrayDiffDeep($value, $b[$key]);
            if (!empty($subDiff)) {
                $diff[$key] = $subDiff;
            }
        } elseif ($value !== $b[$key]) {
            $diff[$key] = $value;
        }
    }

    return $diff;
}

$a = ['a' => 1, 'b' => ['c' => 2, 'd' => 3], 'e' => 4];
$b = ['b' => ['c' => 2, 'd' => 5], 'e' => 4, 'f' => 6];

print_r(deepMerge($a, $b));
print_r(arrayDiffDeep($a, $b));
echo "OK\n";
