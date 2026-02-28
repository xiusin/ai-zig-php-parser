<?php
function maxArr($arr) { $m = $arr[0]; foreach ($arr as $v) { if ($v > $m) $m = $v; } return $m; } echo maxArr(array(3,1,4,1,5));?>
