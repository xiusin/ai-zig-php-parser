<?php
$arr = range(1, 20); $evens = array_filter($arr, function($x) { return $x % 2 == 0; }); echo array_sum($evens);?>
