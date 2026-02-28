<?php
$arr = range(1, 8); $mapped = array_map(function($x) { return $x * $x; }, $arr); echo implode(",", $mapped);?>
