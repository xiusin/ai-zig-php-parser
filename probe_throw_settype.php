<?php
$a = 42;
try { $r = settype($a, "bogus_type"); var_dump($r); } catch (Error $e) { echo "caught: ", get_class($e), ": ", $e->getMessage(), "\n"; }
var_dump($a);
