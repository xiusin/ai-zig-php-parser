<?php
function tailSum($n, $acc = 0) {
    if ($n <= 0) {
        return $acc;
    }
    return tailSum($n - 1, $acc + $n);
}

echo "Sum 1-100: " . tailSum(100) . "\n";
echo "Sum 1-1000: " . tailSum(1000) . "\n";
