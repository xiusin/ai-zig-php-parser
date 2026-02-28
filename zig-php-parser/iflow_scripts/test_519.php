<?php
function lcm($a, $b) { return $a * $b / gcd($a, $b); } function gcd($a, $b) { while ($b != 0) { $t = $b; $b = $a % $b; $a = $t; } return $a; } echo lcm(4, 6);?>
