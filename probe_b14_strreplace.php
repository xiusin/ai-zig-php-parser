<?php
$c = 0;
$r = str_replace('x', 'y', 'xax', $c);
var_dump($r, $c);
$c2 = 0;
$r2 = str_replace(['a','b'], ['1','2'], 'abc', $c2);
var_dump($r2, $c2);
$arr = [3, 1, 2];
sort($arr);
echo json_encode($arr), "\n";
$r3 = preg_replace('/x/', 'y', 'xax', -1, $c3);
var_dump($r3, $c3);
