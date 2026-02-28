<?php
$arr = range(1, 20); $mapped = array_map(function($x) { return $x * 2; }, $arr); echo array_sum(array_slice($mapped, 0, 5));?>
