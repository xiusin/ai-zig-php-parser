<?php
$arr = array("b"=>2, "a"=>1, "c"=>3); ksort($arr); echo implode(",", array_keys($arr));?>
