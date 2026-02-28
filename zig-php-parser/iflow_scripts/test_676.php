<?php
$arr = range(1, 15); $filtered = array_filter($arr, function($x) { return $x % 3 == 0; }); echo array_product($filtered);?>
