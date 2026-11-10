<?php
function f() {
    try {
        $r = array_map(function($v) { if ($v == 2) throw new Exception("m2"); return $v * 10; }, [1, 2, 3]);
        echo json_encode($r), "\n";
    } catch (Exception $e) { echo "fcaught: ", $e->getMessage(), "\n"; }
    echo "fdone\n";
}
f();
