<?php
$r = preg_split('/\s+/', 'title', 2);
var_dump(count($r));
var_dump(isset($r[1]));
$r2 = preg_split('/\s+/', 'a  b  ', 2);
var_dump(count($r2));
var_dump($r2);
