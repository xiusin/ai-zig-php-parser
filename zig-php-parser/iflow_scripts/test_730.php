<?php
$arr = array(1, 2, 3, 4, 5); echo array_reduce($arr, function($c, $i) { return min($c, $i); }, 999);?>
