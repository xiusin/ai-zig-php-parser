<?php
$arr = range(1, 10); echo array_sum(array_map(function($x) { return $x * $x; }, $arr));?>
