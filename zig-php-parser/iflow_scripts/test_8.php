<?php

$x = 5;
$y = 10;
$result = $x > 0 ? ($y > 0 ? ($x > $y ? "x>y" : "y>=x") : "y<=0") : "x<=0";
echo $result;

?>
