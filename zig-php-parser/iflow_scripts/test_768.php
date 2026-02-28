<?php
$arr = array(1, 2, 3); $x = array_reduce($arr, function($c, $i) { return $c + $i; }, 0); echo $x;?>
