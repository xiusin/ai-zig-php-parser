<?php
// 测试加法链累加器传递

function test_simple_add() {
    $sum = 0;
    for ($i = 0; $i < 3; $i++) {
        $sum += $i;
    }
    return $sum;
}

function test_add_chain() {
    $sum = 0;
    for ($i = 0; $i < 3; $i++) {
        for ($j = 0; $j < 3; $j++) {
            $sum += $i + $j;
        }
    }
    return $sum;
}

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

$r1 = test_simple_add();
$r2 = test_add_chain();
$r3 = test_triple_add();

echo "Simple: $r1 (expect 3)\n";
echo "Chain2: $r2 (expect 18)\n";
echo "Chain3: $r3 (expect 81)\n";
