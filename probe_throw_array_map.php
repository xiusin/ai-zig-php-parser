<?php
$a = [1, 2, 3];
try {
    $r = array_map(function($v) { if ($v >= 2) throw new Exception("boom"); return $v * 10; }, $a);
    echo json_encode($r), "\n";
} catch (Exception $e) { echo "caught: ", $e->getMessage(), "\n"; }
echo "done\n";
