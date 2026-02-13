<?php
$sum = 0;
for ($i = 0; $i < 10; $i++) {
    for ($j = 0; $j < 10; $j++) {
        $sum += $i * $j;
    }
    echo "After inner loop: i=$i, sum=$sum\n";
}
echo "Test 2: $sum\n";
