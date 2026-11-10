<?php
$a = ['x' => 1, 'y' => 2];
try {
    $r = array_filter($a, function($k) { throw new Exception("keymode"); }, ARRAY_FILTER_USE_KEY);
    echo json_encode($r), "\n";
} catch (Exception $e) { echo "caught: ", $e->getMessage(), "\n"; }
echo "end\n";
