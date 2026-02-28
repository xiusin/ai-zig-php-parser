<?php

$x = null;
$y = $x ?? "default";
$z = "value";
$w = $z ?? "default";
echo $y . $w;

?>
