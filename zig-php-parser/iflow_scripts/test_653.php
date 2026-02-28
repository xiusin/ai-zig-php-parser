<?php
$arr = range(1, 10); $filtered = array_filter($arr, function($x) { return $x > 5; }); echo array_sum($filtered);?>
