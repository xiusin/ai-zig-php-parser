<?php

echo "Testing ternary operator...\n";

$x = 10;
$y = ($x > 5) ? "large" : "small";
echo "x = $x, y = $y\n";

$a = 3;
$b = ($a < 5) ? $a * 2 : $a + 10;
echo "a = $a, b = $b\n";

$result = ($x > $a) ? ($x + $a) : ($x - $a);
echo "result = $result\n";

echo "Done!\n";
