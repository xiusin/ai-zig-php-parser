<?php
$n = 8; $fib = array(1, 1); for ($i = 2; $i < $n; $i++) { $fib[] = $fib[$i-1] + $fib[$i-2]; } echo implode(",", $fib);?>
