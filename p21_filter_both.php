<?php
$a = ['x' => 1, 'y' => 2, 'z' => 3];
try {
    $r = array_filter($a, function($v, $k) { if ($k == 'y') throw new Exception("both"); return true; }, ARRAY_FILTER_USE_BOTH);
    echo json_encode($r), "\n";
} catch (Exception $e) { echo "caught: ", $e->getMessage(), "\n"; }
echo "end\n";
