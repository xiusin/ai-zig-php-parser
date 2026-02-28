<?php
$x = 1; function outer() { $x = 2; function inner() { return 3; } return inner(); } echo outer();?>
