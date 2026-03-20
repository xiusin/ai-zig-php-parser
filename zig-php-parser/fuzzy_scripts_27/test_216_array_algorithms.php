<?php
function rangeSum(array $nums, int $left, int $right): int {
    $sum = 0;
    for ($i = $left; $i <= $right; $i++) {
        $sum += $nums[$i];
    }
    return $sum;
}

function maxSubArray(array $nums): int {
    $maxSum = $nums[0];
    $currentSum = $nums[0];

    for ($i = 1; $i < count($nums); $i++) {
        $currentSum = max($nums[$i], $currentSum + $nums[$i]);
        $maxSum = max($maxSum, $currentSum);
    }

    return $maxSum;
}

function productExceptSelf(array $nums): array {
    $n = count($nums);
    $result = array_fill(0, $n, 1);

    $prefix = 1;
    for ($i = 0; $i < $n; $i++) {
        $result[$i] = $prefix;
        $prefix *= $nums[$i];
    }

    $postfix = 1;
    for ($i = $n - 1; $i >= 0; $i--) {
        $result[$i] *= $postfix;
        $postfix *= $nums[$i];
    }

    return $result;
}

$nums = [1, 2, 3, 4, 5];
echo rangeSum($nums, 1, 3) . "\n";

$arr = [-2, 1, -3, 4, -1, 2, 1, -5, 4];
echo maxSubArray($arr) . "\n";

echo implode(',', productExceptSelf($nums)) . "\n";
echo "OK\n";
