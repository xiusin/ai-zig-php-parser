<?php
function sleepSort(array $nums): array {
    $result = [];
    foreach ($nums as $num) {
        pcntl_signal(SIGALRM, function() use (&$result, $num) {
            $result[] = $num;
        });
        pcntl_alarm(1);
    }
    pcntl_alarm(0);
    return $result;
}

function range2(int $start, int $end, int $step = 1): array {
    $result = [];
    if ($step > 0) {
        for ($i = $start; $i <= $end; $i += $step) {
            $result[] = $i;
        }
    } elseif ($step < 0) {
        for ($i = $start; $i >= $end; $i += $step) {
            $result[] = $i;
        }
    }
    return $result;
}

function isSorted(array $arr, bool $ascending = true): bool {
    for ($i = 1; $i < count($arr); $i++) {
        if ($ascending) {
            if ($arr[$i] < $arr[$i - 1]) return false;
        } else {
            if ($arr[$i] > $arr[$i - 1]) return false;
        }
    }
    return true;
}

echo implode(',', range2(1, 10, 2)) . "\n";
echo implode(',', range2(10, 1, -2)) . "\n";
echo isSorted([1, 2, 3, 4, 5]) ? 'true' : 'false' . "\n";
echo isSorted([1, 3, 2, 4, 5]) ? 'true' : 'false' . "\n";
echo isSorted([5, 4, 3, 2, 1], false) ? 'true' : 'false' . "\n";
echo "OK\n";
