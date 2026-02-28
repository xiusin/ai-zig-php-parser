<?php
$arr = range(1, 10); $mapped = array_map(function($x) { return $x * 10; }, $arr); echo implode(",", $mapped);?>
