<?php
$sum = 0;
for ($i = 0; $i < 5; $i++) {
    for ($j = 0; $j < 5; $j++) {
        for ($k = 0; $k < 5; $k++) {
            $sum += $i * $j * $k;
        }
    }
}
echo "3-level nested: $sum\n";
$expected = 0;
for ($i = 0; $i < 5; $i++) {
    for ($j = 0; $j < 5; $j++) {
        for ($k = 0; $k < 5; $k++) {
            $expected += $i * $j * $k;
        }
    }
}
if ($sum == $expected) {
    echo "PASS\n";
} else {
    echo "ERROR: Expected $expected\n";
}
