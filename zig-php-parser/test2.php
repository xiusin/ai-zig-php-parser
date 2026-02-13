<?php
function test_nested_loop() {
    $sum = 0;
    for ($i = 0; $i < 10; $i++) {
        for ($j = 0; $j < 10; $j++) {
            $sum += $i * $j;
        }
    }
    return $sum;
}

echo "Test 2: ";
$r2 = test_nested_loop();
echo "$r2\n";

if ($r2 != 2025) {
    echo "ERROR: Expected 2025\n";
} else {
    echo "PASS\n";
}
