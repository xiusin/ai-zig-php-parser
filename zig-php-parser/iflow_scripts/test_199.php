<?php

$keys = ["a", "b", "c"];
$values = [1, 2, 3];
$combined = array_combine($keys, $values);
echo $combined["a"] + $combined["b"] + $combined["c"];

?>
