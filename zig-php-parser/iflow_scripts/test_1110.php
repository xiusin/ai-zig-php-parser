<?php
$arr = array(1, 2, 3, 4, 5); echo array_reduce($arr, function($carry, $item) { return $carry + $item; }, 0);?>
