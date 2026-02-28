<?php
function outer() { $x = 10; function inner() { global $x; return $x + 1; } return inner(); } echo outer();?>
