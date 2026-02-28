<?php
$arr = array(1, 2, 3, 4, 5); echo array_sum(array_filter($arr, function($x) { return $x > 3; }));?>
