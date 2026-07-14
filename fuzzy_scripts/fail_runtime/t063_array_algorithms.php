<?php
// 数组算法：二分查找、两数之和、最长无重复子串、滑动窗口

function binary_search(array $arr, int $target): int {
    $left = 0;
    $right = count($arr) - 1;
    while ($left <= $right) {
        $mid = intdiv($left + $right, 2);
        if ($arr[$mid] === $target) return $mid;
        if ($arr[$mid] < $target) {
            $left = $mid + 1;
        } else {
            $right = $mid - 1;
        }
    }
    return -1;
}

function two_sum(array $nums, int $target): ?array {
    $map = [];
    for ($i = 0; $i < count($nums); $i++) {
        $complement = $target - $nums[$i];
        if (isset($map[$complement])) {
            return [$map[$complement], $i];
        }
        $map[$nums[$i]] = $i;
    }
    return null;
}

function two_sum_sorted(array $nums, int $target): ?array {
    $left = 0;
    $right = count($nums) - 1;
    while ($left < $right) {
        $sum = $nums[$left] + $nums[$right];
        if ($sum === $target) return [$left, $right];
        if ($sum < $target) {
            $left++;
        } else {
            $right--;
        }
    }
    return null;
}

function longest_substring_without_repeating(string $s): int {
    $charSet = [];
    $left = 0;
    $maxLen = 0;
    for ($right = 0; $right < strlen($s); $right++) {
        while (isset($charSet[$s[$right]])) {
            unset($charSet[$s[$left]]);
            $left++;
        }
        $charSet[$s[$right]] = true;
        $maxLen = max($maxLen, $right - $left + 1);
    }
    return $maxLen;
}

function max_subarray_sum(array $nums): int {
    $maxSoFar = $nums[0];
    $maxEndingHere = $nums[0];
    for ($i = 1; $i < count($nums); $i++) {
        $maxEndingHere = max($nums[$i], $maxEndingHere + $nums[$i]);
        $maxSoFar = max($maxSoFar, $maxEndingHere);
    }
    return $maxSoFar;
}

function container_with_most_water(array $height): int {
    $left = 0;
    $right = count($height) - 1;
    $maxArea = 0;
    while ($left < $right) {
        $width = $right - $left;
        $h = min($height[$left], $height[$right]);
        $maxArea = max($maxArea, $width * $h);
        if ($height[$left] < $height[$right]) {
            $left++;
        } else {
            $right--;
        }
    }
    return $maxArea;
}

// 测试 binary_search
$sorted = [1, 3, 5, 7, 9, 11, 13, 15, 17, 19];
echo "binary_search_7: " . binary_search($sorted, 7) . "\n";
echo "binary_search_19: " . binary_search($sorted, 19) . "\n";
echo "binary_search_8: " . binary_search($sorted, 8) . "\n";

// 测试 two_sum
$nums = [2, 7, 11, 15, 3, 6, 8, 4];
$result = two_sum($nums, 10);
echo "two_sum: [" . implode(',', $result) . "]\n";
echo "two_sum_none: " . json_encode(two_sum($nums, 100)) . "\n";

// 测试 two_sum_sorted
$sortedNums = [1, 2, 3, 4, 5, 6, 7, 8, 9];
$result2 = two_sum_sorted($sortedNums, 17);
echo "two_sum_sorted: [" . implode(',', $result2) . "]\n";

// 测试 longest_substring_without_repeating
echo "longest_substr: " . longest_substring_without_repeating("abcabcbb") . "\n";
echo "longest_substr_2: " . longest_substring_without_repeating("bbbbb") . "\n";
echo "longest_substr_3: " . longest_substring_without_repeating("pwwkew") . "\n";

// 测试 max_subarray_sum
echo "max_subarray: " . max_subarray_sum([-2, 1, -3, 4, -1, 2, 1, -5, 4]) . "\n";

// 测试 container_with_most_water
echo "max_water: " . container_with_most_water([1, 8, 6, 2, 5, 4, 8, 3, 7]) . "\n";
