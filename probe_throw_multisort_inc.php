<?php
$a = [3, 1, 2]; $b = [1, 2];
try { $r = array_multisort($a, $b); var_dump($r); } catch (Error $e) { echo "caught: ", get_class($e), ": ", $e->getMessage(), "\n"; }
echo json_encode($a), " ", json_encode($b), "\n";
