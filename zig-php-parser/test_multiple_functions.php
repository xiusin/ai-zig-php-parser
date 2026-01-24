<?php
function add($a, $b) {
    return $a + $b;
}

function multiply($a, $b) {
    return $a * $b;
}

function calculate($x, $y) {
    $sum = add($x, $y);
    $product = multiply($x, $y);
    return add($sum, $product);
}

$result = calculate(3, 4);
echo $result;
