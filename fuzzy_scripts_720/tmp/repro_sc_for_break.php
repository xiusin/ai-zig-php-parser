<?php
function findFirstEven(array $nums): int {
    $n = 0;
    for ($i = 0; $i < count($nums); $i++) {
        if ($nums[$i] % 2 === 0) break;
        $n = $nums[$i];
    }
    return $n;
}
$nums = [1, 3, 5, 8, 9];
echo findFirstEven($nums) . "\n";
echo "DONE\n";
