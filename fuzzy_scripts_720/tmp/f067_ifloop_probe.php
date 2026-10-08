<?php
function scan(mixed $x, string $tag): string {
    $out = '';
    if (is_array($x)) {
        foreach ($x as $k => $v) {
            if ($v === null) continue;
            $out .= $tag . ':' . $k . '=' . $v . ';';
        }
    } else {
        $out = $tag . ':scalar=' . $x;
    }
    return $out;
}
echo scan([1, 2, 3], 'a') . "\n";
echo scan('hello', 'b') . "\n";
echo scan([], 'c') . "\n";
echo scan(['x' => 1, 'y' => null, 'z' => 3], 'd') . "\n";

function nested(mixed $a, mixed $b): int {
    $n = 0;
    if (is_array($a) && is_array($b)) {
        foreach ($a as $k => $v) {
            if (!array_key_exists($k, $b)) { $n += 1; continue; }
            if ($v !== $b[$k]) { $n += 2; }
        }
    } elseif ($a !== $b) {
        $n = 99;
    }
    return $n;
}
echo nested([1, 2, 3], [1, 5, 3]) . "\n";
echo nested([1, 2], [1, 2, 3]) . "\n";
echo nested(7, 8) . "\n";
echo nested(7, 7) . "\n";
