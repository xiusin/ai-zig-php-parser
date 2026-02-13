<?php
$iterations = 1000;

for ($iter = 0; $iter < $iterations; $iter++) {
    $sum = 0;
    for ($i = 0; $i < 100; $i++) {
        for ($j = 0; $j < 100; $j++) {
            $sum += $i * $j;
        }
    }
}

echo "Result: $sum\n";
