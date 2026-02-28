<?php
$arr = array("c"=>3, "a"=>1, "b"=>2); ksort($arr); echo implode(",", array_keys($arr));?>
