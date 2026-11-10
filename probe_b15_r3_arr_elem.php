<?php
function byref(&$x) { $x = 77; }
$a = ['k' => 1];
byref($a['missing']);
var_dump($a);
$b = [];
byref($b['new']['deep']);
var_dump($b);
