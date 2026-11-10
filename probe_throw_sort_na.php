<?php
$a = "str";
try { $r = sort($a); var_dump($r); } catch (Error $e) { echo "caught: ", get_class($e), ": ", $e->getMessage(), "\n"; }
var_dump($a);
