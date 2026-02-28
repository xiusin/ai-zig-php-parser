<?php

$x = 5;
$y = 10;
$z = 15;
if (($x < $y && $y < $z) || ($x > $z)) {
    echo "condition1";
} elseif (($x == 5) || ($y == 10 && $z == 15)) {
    echo "condition2";
} else {
    echo "other";
}

?>
