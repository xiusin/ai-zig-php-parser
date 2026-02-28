<?php

$arr = ["a" => 1, "b" => 2, "c" => 3];
extract($arr);
echo $a + $b + $c;

?>
