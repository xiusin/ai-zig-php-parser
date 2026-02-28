<?php
$arr = array(1, 2, 3); echo array_sum(array_filter($arr, function($x) { return true; }));?>
