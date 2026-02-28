<?php
$arr = array(1, 2, 3, 4, 5); $filtered = array(); foreach ($arr as $v) { if ($v % 2 == 0) $filtered[] = $v; } echo implode(",", $filtered);?>
