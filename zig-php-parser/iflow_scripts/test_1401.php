<?php
$x = 10; $arr = array(); for ($i = 1; $i <= $x; $i++) { if ($x % $i == 0) $arr[] = $i; } echo implode(",", $arr);?>
