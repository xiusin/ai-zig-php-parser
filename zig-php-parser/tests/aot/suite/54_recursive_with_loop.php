<?php
function f($n) {
    if ($n <= 0) return 0;
    $acc = 0;
    for ($i = 0; $i < $n; $i++) {
        $acc += $i;
    }
    return $acc + f($n - 1);
}
$res = f(4);
echo "RecLoop: $res (expect 10)\n";
