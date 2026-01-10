<?php
/**
 * Simple list test
 */
$arr = [1, 2, 3];
echo "Array: ";
var_dump($arr);

list($a, $b, $c) = $arr;
echo "List result: $a, $b, $c\n";

