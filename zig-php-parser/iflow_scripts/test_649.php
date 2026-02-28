<?php
$arr = array(array(1,2), array(3,4), array(5,6)); $sum = 0; for ($i = 0; $i < count($arr); $i++) { for ($j = 0; $j < count($arr[$i]); $j++) { $sum += $arr[$i][$j]; } } echo $sum;?>
