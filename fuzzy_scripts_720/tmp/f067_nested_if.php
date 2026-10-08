<?php
function num(string $s, int $p0, int $len): string {
    $pos = $p0;
    $r = 'no';
    if ($pos < $len && ($s[$pos] === 'e' || $s[$pos] === 'E')) {
        $r = 'exp';
        $pos = $pos + 1;
        if ($pos < $len && ($s[$pos] === '+' || $s[$pos] === '-')) $pos = $pos + 1;
        while ($pos < $len && $s[$pos] >= '0' && $s[$pos] <= '9') $pos = $pos + 1;
    }
    return $r . ':' . $pos;
}
echo num('1e5', 1, 3) . "\n";
echo num('1e+5', 1, 4) . "\n";
echo num('1e', 1, 2) . "\n";
echo num('1x', 1, 2) . "\n";
