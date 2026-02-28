<?php

$arr = [1, 2, 3, 4, 5];
$sum = 0;
array_map(function($x) use (&$sum) {
    $sum += $x;
}, $arr);
echo $sum;

?>
