<?php

function add($a, $b) { return $a + $b; }
function mul($a, $b) { return $a * $b; }
function sub($a, $b) { return $a - $b; }
$result = sub(mul(add(1, 2), 3), 4);
echo $result;

?>
