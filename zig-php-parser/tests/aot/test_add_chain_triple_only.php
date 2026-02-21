<?php
function test_triple_add() {
    $sum = 0;
    for ($i = 0; $i < 3; $i++) {
        for ($j = 0; $j < 3; $j++) {
            for ($k = 0; $k < 3; $k++) {
                $sum += $i + $j + $k;
            }
        }
    }
    return $sum;
}

echo "Chain3: " . test_triple_add() . " (expect 81)\n";
