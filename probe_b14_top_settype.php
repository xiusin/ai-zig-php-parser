<?php
$a = 1;
settype($a, "bogus");
echo "unreachable\n";
