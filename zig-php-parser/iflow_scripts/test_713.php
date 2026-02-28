<?php
$arr = range(1, 10); $mapped = array_map(function($x) { return $x * $x; }, $arr); echo array_sum(array_slice($mapped, 0, 5));?>
