<?php

$x = 5;
$y = 10;
$z = 15;
$result = ($x > 3 && $y < 20) || ($z == 15 && $x + $y > $z) ? ($x * $y) + ($z / 3) : ($x - $y) * $z;
echo $result;

?>
