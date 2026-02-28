<?php
$arr = array(1, 2, 3, 4, 5); $x = array_map(function($i) { return $i * $i; }, $arr); echo implode(",", $x);?>
