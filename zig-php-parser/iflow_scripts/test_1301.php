<?php
$fib = array(1, 1); for ($i = 2; $i < 20; $i++) { $fib[] = $fib[$i-1] + $fib[$i-2]; } echo $fib[19];?>
