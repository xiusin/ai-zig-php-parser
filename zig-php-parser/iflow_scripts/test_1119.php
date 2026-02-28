<?php
$arr = array("b" => 2, "a" => 1, "c" => 3); krsort($arr); echo implode(",", array_keys($arr));?>
