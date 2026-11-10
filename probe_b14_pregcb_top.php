<?php
$c = 5;
preg_replace_callback('/x/', function($m) { throw new Exception("top"); }, 'xax', -1, $c);
echo "unreachable\n";
