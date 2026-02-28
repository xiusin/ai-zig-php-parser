<?php
$x = 17; $isPrime = true; for ($i = 2; $i <= sqrt($x); $i++) { if ($x % $i == 0) { $isPrime = false; break; } } echo $isPrime ? "prime" : "not";?>
