<?php
$a = [3, 1, 2];
usort($a, function($x, $y) { throw new Exception("boom"); });
echo "unreachable\n";
