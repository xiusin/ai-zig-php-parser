<?php

$arr = ["b" => 2, "a" => 1, "d" => 4, "c" => 3];
asort($arr);
echo implode(",", $arr);
arsort($arr);
echo implode(",", $arr);

?>
