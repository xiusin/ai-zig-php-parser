<?php
function countChars($s) { $c = array(); for ($i = 0; $i < strlen($s); $i++) { $ch = $s[$i]; $c[$ch] = isset($c[$ch]) ? $c[$ch]+1 : 1; } return $c; } print_r(countChars("hello"));?>
