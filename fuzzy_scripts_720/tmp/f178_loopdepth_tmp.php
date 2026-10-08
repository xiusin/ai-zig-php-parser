<?php
echo "=== f178 loop-depth bisection ===\n";

function tri(int $n): int {
    $x = 0;
    for ($i = 0; $i < $n; $i++) {
        for ($j = 0; $j < $n; $j++) {
            for ($k = 0; $k < $n; $k++) {
                $x = $x + 1;
            }
        }
    }
    return $x;
}

function dos(int $n): int {
    $x = 0;
    for ($i = 0; $i < $n; $i++) {
        for ($j = 0; $j < $n; $j++) {
            $x = $x + 1;
        }
    }
    return $x;
}

function uni(int $n): int {
    $x = 0;
    for ($i = 0; $i < $n; $i++) {
        $x = $x + 1;
    }
    return $x;
}

echo "uni=" . uni(3) . "\n";
echo "dos=" . dos(3) . "\n";
echo "tri=" . tri(3) . "\n";
echo "=== done ===\n";
