<?php
$arr = array(1,2,3,4,5); $mapped = array_map(function($x) { return $x * 10; }, $arr); echo implode(",", $mapped);?>
