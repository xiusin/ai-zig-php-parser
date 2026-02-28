<?php
$arr = array(1,2,3); unset($arr[1]); echo implode(",", array_values($arr));?>
