<?php
$arr = array(1, 2, 3, 4, 5); $arr2 = array_filter($arr, function($x) { return $x != 3; }); echo implode(",", $arr2);?>
