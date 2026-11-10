<?php
$a = [[1, 2], [3, 4]];
try {
    array_walk_recursive($a, function(&$v, $k) { if ($v >= 2) throw new Exception("boom"); $v *= 10; });
} catch (Exception $e) { echo "caught: ", $e->getMessage(), "\n"; }
echo json_encode($a), "\n";
