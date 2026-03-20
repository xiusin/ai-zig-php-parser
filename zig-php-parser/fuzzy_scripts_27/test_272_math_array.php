<?php
function sum2(array $nums): int|float {
    return array_sum($nums);
}

function product(array $nums): int|float {
    return array_reduce($nums, fn($carry, $n) => $carry * $n, 1);
}

function sumOfSquares(array $nums): int|float {
    return array_reduce($nums, fn($carry, $n) => $carry + $n ** 2, 0);
}

function sumOfCubes(array $nums): int|float {
    return array_reduce($nums, fn($carry, $n) => $carry + $n ** 3, 0);
}

function arithmeticMean(array $nums): float {
    return empty($nums) ? 0.0 : sum2($nums) / count($nums);
}

function geometricMean(array $nums): float {
    if (empty($nums)) return 0.0;
    return pow(product($nums), 1 / count($nums));
}

echo sum2([1, 2, 3, 4, 5]) . "\n";
echo product([1, 2, 3, 4, 5]) . "\n";
echo sumOfSquares([1, 2, 3]) . "\n";
echo arithmeticMean([1, 2, 3, 4, 5]) . "\n";
echo sprintf("%.2f\n", geometricMean([2, 4, 8]));
echo "OK\n";
