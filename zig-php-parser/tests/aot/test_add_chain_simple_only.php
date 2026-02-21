<?php
function test_simple_add() {
    $sum = 0;
    for ($i = 0; $i < 3; $i++) {
        $sum += $i;
    }
    return $sum;
}

echo "Simple: " . test_simple_add() . " (expect 3)\n";
