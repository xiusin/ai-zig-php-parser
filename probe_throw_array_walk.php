<?php
$a = [1, 2, 3, 4, 5];
try {
    array_walk($a, function(&$v, $k) {
        if ($k >= 2) throw new Exception("boom");
        $v = $v * 10;
    });
} catch (Exception $e) { echo "caught: ", $e->getMessage(), "\n"; }
echo json_encode($a), "\n";
