<?php
$arr = array(1, 2, 3, 4, 5); echo array_sum(array_map(function($x) { return $x * $x * $x; }, $arr));?>
