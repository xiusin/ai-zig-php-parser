<?php
$arr = array(1, 2, 3); $arr2 = array_map(function($x) { return $x * 2; }, $arr); echo implode(",", $arr2);?>
