<?php
function isEven(int $n): bool {
    return $n % 2 === 0;
}

function isOdd(int $n): bool {
    return $n % 2 !== 0;
}

function isPositive(int|float $n): bool {
    return $n > 0;
}

function isNegative(int|float $n): bool {
    return $n < 0;
}

function isDivisibleBy(int $n, int $divisor): bool {
    return $divisor !== 0 && $n % $divisor === 0;
}

function clamp(int|float $value, int|float $min, int|float $max): int|float {
    if ($value < $min) return $min;
    if ($value > $max) return $max;
    return $value;
}

function inRange(int|float $value, int|float $min, int|float $max): bool {
    return $value >= $min && $value <= $max;
}

echo isEven(4) ? 'true' : 'false' . "\n";
echo isOdd(3) ? 'true' : 'false' . "\n";
echo isPositive(10) ? 'true' : 'false' . "\n";
echo isNegative(-5) ? 'true' : 'false' . "\n";
echo isDivisibleBy(10, 5) ? 'true' : 'false' . "\n";
echo clamp(15, 0, 10) . "\n";
echo inRange(5, 0, 10) ? 'true' : 'false' . "\n";
echo "OK\n";
