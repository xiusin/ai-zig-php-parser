<?php

$a = [1, 2, 3, 4];
$b = [2, 4];
$diff = array_diff($a, $b);
echo implode(",", $diff);

?>
