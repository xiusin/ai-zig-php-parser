<?php
// f161 探针4：最小 while 短路条件 + 双自增
function w2(): string {
    $s = '  <a>';
    $p = 0;
    $g = 0;
    while ($p < strlen($s) && ctype_space($s[$p])) {
        $p++;
        $g++;
        if ($g > 500) break;
    }
    return "w2 p={$p} g={$g}";
}

function w1(): string {
    $p = 0;
    $g = 0;
    while ($p < 3) {
        $p++;
        $g++;
    }
    return "w1 p={$p} g={$g}";
}

function w3(): string {
    $s = '  <a>';
    $p = 0;
    while ($p < strlen($s)) {
        $p++;
    }
    return "w3 p={$p}";
}

function w4(): string {
    $s = '  <a>';
    $p = 0;
    while (ctype_space($s[$p])) {
        $p++;
    }
    return "w4 p={$p}";
}

echo w1() . "\n";
echo w2() . "\n";
echo w3() . "\n";
echo w4() . "\n";
