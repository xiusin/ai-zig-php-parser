<?php
$arr = array(1, 5, 3, 8, 2); $min = $arr[0]; for ($i = 1; $i < count($arr); $i++) { if ($arr[$i] < $min) $min = $arr[$i]; } echo $min;?>
