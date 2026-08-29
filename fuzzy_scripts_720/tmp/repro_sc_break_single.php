<?php
function findFirstEven(array $nums): int {
    foreach ($nums as $n) {
        if ($n % 2 === 0) break;
    }
    return $n;
}
$nums = [1, 3, 5, 8, 9];
echo findFirstEven($nums) . "\n";
echo "DONE\n";
