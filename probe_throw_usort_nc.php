<?php
$a = [3, 1, 2];
try { usort($a, "nonexistent_fn_xyz"); } catch (Error $e) { echo "caught: ", get_class($e), ": ", $e->getMessage(), "\n"; }
echo json_encode($a), "\n";
