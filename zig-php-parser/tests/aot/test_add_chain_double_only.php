<?php
function test_add_chain() {
    $sum = 0;
    for ($i = 0; $i < 3; $i++) {
        for ($j = 0; $j < 3; $j++) {
            $sum += $i + $j;
        }
    }
    return $sum;
}

echo "Chain2: " . test_add_chain() . " (expect 18)\n";
