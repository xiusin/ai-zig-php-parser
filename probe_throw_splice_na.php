<?php
$a = "str";
try { $r = array_splice($a, 0); var_dump($r); } catch (Error $e) { echo "caught: ", get_class($e), ": ", $e->getMessage(), "\n"; }
var_dump($a);
