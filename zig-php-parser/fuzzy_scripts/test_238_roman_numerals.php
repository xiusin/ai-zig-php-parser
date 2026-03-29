<?php
function romanToInt(string $s): int {
    $map = ['I' => 1, 'V' => 5, 'X' => 10, 'L' => 50, 'C' => 100, 'D' => 500, 'M' => 1000];
    $result = 0;
    $prev = 0;

    for ($i = strlen($s) - 1; $i >= 0; $i--) {
        $curr = $map[$s[$i]];
        if ($curr < $prev) {
            $result -= $curr;
        } else {
            $result += $curr;
        }
        $prev = $curr;
    }

    return $result;
}

function intToRoman(int $num): string {
    $vals = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
    $syms = ['M', 'CM', 'D', 'CD', 'C', 'XC', 'L', 'XL', 'X', 'IX', 'V', 'IV', 'I'];
    $result = '';

    for ($i = 0; $i < count($vals); $i++) {
        while ($num >= $vals[$i]) {
            $result .= $syms[$i];
            $num -= $vals[$i];
        }
    }

    return $result;
}

echo romanToInt('III') . "\n";
echo romanToInt('MCMXCIV') . "\n";
echo intToRoman(3) . "\n";
echo intToRoman(1994) . "\n";
echo intToRoman(58) . "\n";
echo "OK\n";
