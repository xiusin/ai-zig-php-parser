<?php
$n = 7; $isPrime = true; for ($i = 2; $i <= sqrt($n); $i++) { if ($n % $i == 0) { $isPrime = false; break; } } echo $isPrime ? "prime" : "not";?>
