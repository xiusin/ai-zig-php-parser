<?php
$arr1 = array("a","b","c"); $arr2 = array(1,2,3); $combined = array_combine($arr1, $arr2); echo implode(",", array_values($combined));?>
