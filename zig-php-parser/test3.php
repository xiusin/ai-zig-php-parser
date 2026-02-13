<?php
// Test 3: 三层嵌套
$sum = 0;
for ($i = 0; $i < 5; $i++) {
    for ($j = 0; $j < 5; $j++) {
        for ($k = 0; $k < 5; $k++) {
            $sum += $i * $j * $k;
        }
    }
}

if ($sum == 1000) {
    echo "Test 3: $sum\n";
    echo "PASS\n";
} else {
    echo "Test 3: $sum\n";
    echo "ERROR: Expected 1000\n";
}
