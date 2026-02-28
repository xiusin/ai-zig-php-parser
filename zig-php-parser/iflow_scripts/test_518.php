<?php
function gcd($a, $b) { while ($b != 0) { $t = $b; $b = $a % $b; $a = $t; } return $a; } echo gcd(48, 18);?>
