<?php
$arr = array(1, 2, 3); echo implode("", array_map(function($x) { return $x * 2; }, $arr));?>
