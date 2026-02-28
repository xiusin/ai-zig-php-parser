<?php
$arr = array(1, 2, 3, 4, 5); $found = false; foreach ($arr as $v) { if ($v == 4) { $found = true; break; } } echo $found ? "found" : "not";?>
