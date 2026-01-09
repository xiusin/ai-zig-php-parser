<?php
function nested($level, $max) {
    if ($level >= $max) {
        return $level;
    }
    $sum = 0;
    for ($i = 0; $i < 3; $i++) {
        $sum += nested($level + 1, $max);
    }
    return $sum;
}

echo "Nested result: " . nested(0, 4) . "\n";
