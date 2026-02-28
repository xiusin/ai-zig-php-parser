<?php
$arr = array(1,2,3,4,5); $filtered = array_filter($arr, function($x) { return $x > 2; }); echo implode(",", $filtered);?>
