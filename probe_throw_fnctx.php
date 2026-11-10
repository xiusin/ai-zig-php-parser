<?php
function work() {
    $a = [3, 1, 2];
    try {
        usort($a, function($x, $y) { throw new Exception("fn-boom"); });
    } catch (Exception $e) {
        echo "fn caught: ", $e->getMessage(), "\n";
    }
    sort($a);
    echo json_encode($a), "\n";
    return $a;
}
work();
echo "done\n";
