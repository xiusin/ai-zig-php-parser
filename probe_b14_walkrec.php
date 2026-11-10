<?php
$a = [[1, 2], [3, 4]];
$r = array_walk_recursive($a, function(&$v, $k) { $v *= 10; });
var_dump($r);
echo json_encode($a), "\n";
$b = ['x' => ['y' => 5], 'z' => 7];
array_walk_recursive($b, function(&$v, $k) { $v += 1; });
echo json_encode($b), "\n";
$c = [[1, 2], [3, 4]];
try {
    array_walk_recursive($c, function(&$v, $k) { if ($v >= 2) throw new Exception("boom"); $v *= 10; });
} catch (Exception $e) { echo "caught: ", $e->getMessage(), "\n"; }
echo json_encode($c), "\n";
$s = "str";
try { array_walk_recursive($s, function(&$v, $k) {}); } catch (TypeError $e) { echo "caught: ", $e->getMessage(), "\n"; }
var_dump($s);
