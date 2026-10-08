<?php
function scanA(array $x): int {
    $n = 0;
    if (count($x) > 0) {
        foreach ($x as $v) {
            if ($v === 5) continue;
            $n = $n + $v;
        }
    } else {
        $n = 99;
    }
    return $n;
}
echo scanA([1, 2, 3]) . "\n";
echo scanA([5, 6]) . "\n";
echo scanA([]) . "\n";

function scanB(array $x): int {
    $n = 0;
    if (count($x) > 1) {
        foreach ($x as $v) {
            $n = $n + $v;
        }
    }
    return $n;
}
echo scanB([4, 5]) . "\n";
echo scanB([7]) . "\n";

function scanC(int $flag, array $x): string {
    if ($flag > 0) {
        foreach ($x as $v) {
            echo "v=$v\n";
        }
        return "looped";
    }
    return "skipped";
}
echo scanC(1, [2, 3]) . "\n";
echo scanC(0, [2, 3]) . "\n";
