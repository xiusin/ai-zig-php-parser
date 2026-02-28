<?php
$arr = range(1, 5); echo array_reduce($arr, function($a, $b) { return ($a < $b) ? $a : $b; });?>
