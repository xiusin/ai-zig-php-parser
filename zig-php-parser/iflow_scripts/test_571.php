<?php
$arr = array(1,2,3,4,5); $fn = function($x) { return $x * 2; }; echo implode(",", array_map($fn, $arr));?>
