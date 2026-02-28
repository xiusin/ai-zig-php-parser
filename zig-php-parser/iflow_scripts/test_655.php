<?php
function recursiveSum($arr, $i = 0) { if ($i >= count($arr)) return 0; return $arr[$i] + recursiveSum($arr, $i + 1); } echo recursiveSum(array(1,2,3,4,5));?>
