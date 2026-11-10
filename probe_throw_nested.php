<?php
$a = [5, 3, 1, 4, 2];
try {
    try {
        usort($a, function($x, $y) { if ($x == 3) throw new LogicException("inner"); return $x <=> $y; });
    } catch (LogicException $e) {
        echo "inner caught: ", $e->getMessage(), "\n";
        throw new RuntimeException("rethrown");
    }
} catch (RuntimeException $e) {
    echo "outer caught: ", $e->getMessage(), "\n";
}
sort($a);
echo json_encode($a), "\n";
