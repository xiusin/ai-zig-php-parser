<?php
function revStr($s) { $r = ""; for ($i = strlen($s)-1; $i >= 0; $i--) { $r .= $s[$i]; } return $r; } echo revStr("hello");?>
