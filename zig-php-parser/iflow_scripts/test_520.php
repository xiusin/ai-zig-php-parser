<?php
$arr = range(1, 20); $even = array_filter($arr, function($x) { return $x % 2 == 0; }); echo array_sum($even);?>
