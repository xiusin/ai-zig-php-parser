<?php

$obj = new stdClass();
$obj->name = "John";
$obj->age = 30;
$prop = "name";
echo $obj->$prop;

?>
