<?php

$arr = ["b" => 2, "a" => 1, "d" => 4, "c" => 3];
ksort($arr);
echo implode(",", $arr);
krsort($arr);
echo implode(",", $arr);

?>
