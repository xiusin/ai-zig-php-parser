<?php
function hopOr(string $s, int $p, int $len, bool $flag): string {
    $r = 'no';
    if ($p < $len && $s[$p] === 'z') {
        $r = 'a';
    }
    if ($p < $len && ($s[$p] === 'e' || $s[$p] === 'E')) {
        $r = 'exp';
    }
    if ($p < $len && ($s[$p] === 'x' || $s[$p] === 'X')) {
        $r = $r . 'z';
    }
    return $r;
}
echo hopOr('1e5', 1, 3, false) . "\n";
echo hopOr('1E5', 1, 3, true) . "\n";
echo hopOr('x', 1, 3, false) . "\n";
