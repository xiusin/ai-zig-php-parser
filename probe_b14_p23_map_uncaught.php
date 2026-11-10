<?php
$a = [1, 2];
$r = array_map(function($v) { throw new Exception("topboom"); }, $a);
echo "unreachable\n";
