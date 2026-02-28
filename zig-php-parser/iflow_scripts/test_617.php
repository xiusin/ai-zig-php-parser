<?php
function sum() { $s = 0; foreach (func_get_args() as $a) { $s += $a; } return $s; } echo sum(1,2,3,4,5);?>
