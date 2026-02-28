<?php

$arr = [1, 2, 3];
$padded = array_pad($arr, 6, 0);
echo implode(",", $padded);

?>
