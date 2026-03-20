<?php
function nthDigit(int $num, int $n): int {
    return (int)(floor($num / pow(10, $n - 1)) % 10);
}

function digitCount(int $num): int {
    return $num === 0 ? 1 : (int)log10(abs($num)) + 1;
}

function sumOfDigits(int $num): int {
    $sum = 0;
    while ($num > 0) {
        $sum += $num % 10;
        $num = (int)($num / 10);
    }
    return $sum;
}

function reverseNumber(int $num): int {
    $reversed = 0;
    while ($num > 0) {
        $reversed = $reversed * 10 + $num % 10;
        $num = (int)($num / 10);
    }
    return $reversed;
}

function isPalindromeNumber(int $num): bool {
    return $num === reverseNumber($num);
}

function isArmstrong(int $num): bool {
    $digits = str_split((string)abs($num));
    $n = count($digits);
    $sum = 0;
    foreach ($digits as $d) {
        $sum += pow((int)$d, $n);
    }
    return $sum === abs($num);
}

echo nthDigit(12345, 3) . "\n";
echo digitCount(12345) . "\n";
echo sumOfDigits(123) . "\n";
echo reverseNumber(12345) . "\n";
echo isPalindromeNumber(121) ? 'true' : 'false' . "\n";
echo isArmstrong(153) ? 'true' : 'false' . "\n";
echo "OK\n";
