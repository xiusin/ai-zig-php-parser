<?php

$str = "  Hello World  ";
$str = trim($str);
$str = strtolower($str);
$str = str_replace("world", "php", $str);
echo $str;

?>
