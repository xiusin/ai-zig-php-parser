<?php
$c = preg_replace('/x/', 'y', 'xax', -1, $cnt);
var_dump($c, $cnt);
$c2 = preg_replace(['/a/', '/b/'], ['1', '2'], 'abc', -1, $cnt2);
var_dump($c2, $cnt2);
$f = preg_filter('/x/', 'y', ['x', 'z', 'xx'], -1, $cnt3);
var_dump($f, $cnt3);
$r = preg_replace('/(\d)(\d)/', '$2$1', 'a12b34', -1, $cnt4);
var_dump($r, $cnt4);
$none = preg_replace('/q/', 'y', 'xax');
var_dump($none);
