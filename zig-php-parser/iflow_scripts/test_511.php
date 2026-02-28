<?php
$arr = array(1, 2, 3, 4, 5); $sum = array_reduce($arr, function($c, $i) { return $c + $i; }); echo $sum;?>
