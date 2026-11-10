<?php
$a = [[1, 2], [3, 4]];
$r = array_walk_recursive($a, function(&$v, $k) { $v *= 10; });
var_dump($r);
echo json_encode($a), "\n";
