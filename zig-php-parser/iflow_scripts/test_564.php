<?php
$arr = range(1, 10); echo array_sum(array_filter($arr, function($x) { return $x % 2 == 1; }));?>
