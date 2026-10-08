<?php
function guardOr(string $s, int $p): string {
    $r = 'no';
    if ($p < strlen($s) && ($s[$p] === 'e' || $s[$p] === 'E')) {
        $r = 'exp';
    }
    return $r;
}
echo guardOr('1e5', 1) . "\n";
echo guardOr('1E5', 1) . "\n";
echo guardOr('1x5', 1) . "\n";
echo guardOr('x', 1) . "\n";
