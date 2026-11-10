<?php
$count = 99;
try {
    preg_replace_callback('/x/', function($m) { throw new Exception("boom"); }, "xax", -1, $count);
} catch (Exception $e) { echo "caught: ", $e->getMessage(), "\n"; }
var_dump($count);
