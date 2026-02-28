<?php
$arr = array(1, 2, 3, 4, 5); echo array_filter($arr, function($x) { return $x % 2 == 1; });?>
