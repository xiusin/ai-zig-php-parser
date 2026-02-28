<?php
$arr = array("c" => 1, "a" => 2, "b" => 3); ksort($arr); echo implode(",", array_keys($arr));?>
