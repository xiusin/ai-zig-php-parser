<?php
function work() {
    $a = [1, 2, 3, 4];
    try {
        $r = array_filter($a, function($v) { if ($v >= 3) throw new Exception("fboom"); return $v % 2 == 0; });
        echo json_encode($r), "\n";
    } catch (Exception $e) { echo "caught: ", $e->getMessage(), "\n"; }
    return "done";
}
echo work(), "\n";
