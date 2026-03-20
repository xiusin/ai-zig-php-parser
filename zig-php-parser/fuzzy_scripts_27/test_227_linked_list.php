<?php
function detectCycle(array $nums): int {
    if (count($nums) < 2) return -1;

    $slow = 0;
    $fast = 0;

    do {
        $slow = $nums[$slow];
        $fast = $nums[$nums[$fast]];
    } while ($slow !== $fast && $fast !== -1 && isset($nums[$nums[$fast]]));

    if ($slow === $fast) {
        $slow = 0;
        while ($slow !== $fast) {
            $slow = $nums[$slow];
            $fast = $nums[$fast];
        }
        return $slow;
    }

    return -1;
}

function findDuplicate(array $nums): int {
    $slow = $nums[0];
    $fast = $nums[$nums[0]];

    while ($slow !== $fast) {
        $slow = $nums[$slow];
        $fast = $nums[$nums[$fast]];
    }

    $slow = 0;
    while ($slow !== $fast) {
        $slow = $nums[$slow];
        $fast = $nums[$fast];
    }

    return $slow;
}

$numsWithCycle = [1, 2, 3, 4, 5, 3];
echo detectCycle($numsWithCycle) . "\n";

$duplicates = [1, 3, 4, 2, 2, 5, 6, 7, 3];
echo findDuplicate($duplicates) . "\n";
echo "OK\n";
