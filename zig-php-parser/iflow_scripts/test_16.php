<?php

function f1($x) { return $x + 1; }
function f2($x) { return $x * 2; }
function f3($x) { return $x - 3; }
echo f1(f2(f3(10)));

?>
