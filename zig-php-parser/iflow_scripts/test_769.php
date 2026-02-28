<?php
$arr = array(1, 2, 3, 4, 5); $x = array_filter($arr, function($i) { return $i % 2 == 1; }); echo implode(",", array_values($x));?>
