<?php
$arr = array(); for ($i = 1; $i <= 5; $i++) { $arr[] = array(); for ($j = 1; $j <= 3; $j++) { $arr[$i-1][] = $i * 10 + $j; } } echo implode(",", $arr[2]);?>
