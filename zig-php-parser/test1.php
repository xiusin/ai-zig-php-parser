<?php
// 只测试 Test 1

function test_simple_loop() {
    $sum = 0;
    for ($i = 0; $i < 1000; $i++) {
        $sum += $i;
    }
    return $sum;
}

echo "Test 1: ";
$r1 = test_simple_loop();
echo "$r1\n";

if ($r1 != 499500) {
    echo "ERROR: Expected 499500\n";
} else {
    echo "PASS\n";
}
