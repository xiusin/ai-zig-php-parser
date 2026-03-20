<?php
function percentage(int|float $value, int|float $total): float {
    if ($total === 0) return 0.0;
    return ($value / $total) * 100;
}

function percentageChange(int|float $old, int|float $new): float {
    if ($old === 0) return 0.0;
    return (($new - $old) / $old) * 100;
}

function roundTo(int|float $value, int $precision): float {
    $mult = pow(10, $precision);
    return round($value * $mult) / $mult;
}

function roundUp(int|float $value, int $precision): float {
    $mult = pow(10, $precision);
    return ceil($value * $mult) / $mult;
}

function roundDown(int|float $value, int $precision): float {
    $mult = pow(10, $precision);
    return floor($value * $mult) / $mult;
}

function absolute(int|float $value): int|float {
    return abs($value);
}

function sign(int|float $value): int {
    if ($value > 0) return 1;
    if ($value < 0) return -1;
    return 0;
}

echo percentage(25, 200) . "\n";
echo percentageChange(100, 150) . "\n";
echo roundTo(3.14159, 3) . "\n";
echo roundUp(3.14159, 3) . "\n";
echo roundDown(3.14159, 3) . "\n";
echo absolute(-42) . "\n";
echo sign(-42) . "\n";
echo "OK\n";
