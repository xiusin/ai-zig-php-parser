<?php
function intersection(array $a, array $b): array {
    return array_values(array_intersect($a, $b));
}

function difference(array $a, array $b): array {
    return array_values(array_diff($a, $b));
}

function symmetricDifference(array $a, array $b): array {
    return array_values(array_diff(array_merge($a, $b), array_intersect($a, $b)));
}

function cartesianProduct(array $a, array $b): array {
    $result = [];
    foreach ($a as $va) {
        foreach ($b as $vb) {
            $result[] = [$va, $vb];
        }
    }
    return $result;
}

$a = [1, 2, 3, 4];
$b = [3, 4, 5, 6];
echo implode(',', intersection($a, $b)) . "\n";
echo implode(',', difference($a, $b)) . "\n";
echo implode(',', symmetricDifference($a, $b)) . "\n";

$product = cartesianProduct(['x', 'y'], [1, 2, 3]);
echo count($product) . "\n";
echo implode(',', $product[0]) . "\n";
echo "OK\n";
