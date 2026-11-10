<?php
$c = 5;
try {
    preg_replace_callback('/x/', function($m) { throw new Exception("stmt"); }, 'xax', -1, $c);
} catch (Exception $e) { echo "caught: ", $e->getMessage(), "\n"; }
var_dump($c);
