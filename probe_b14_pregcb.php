<?php
$c = 99;
$r = preg_replace_callback('/x/', fn($m) => 'Y', 'xax', -1, $c);
var_dump($r, $c);
$c = 99;
$r = preg_replace_callback('/x/', fn($m) => 'Y', 'xax', 1, $c);
var_dump($r, $c);
$c = 99;
$r = preg_replace_callback('/z/', fn($m) => 'Y', 'xax', -1, $c);
var_dump($r, $c);
$c = 99;
try { preg_replace_callback('/x/', function($m) { throw new Exception("boom"); }, 'xax', -1, $c); } catch (Exception $e) { echo "caught: ", $e->getMessage(), "\n"; }
var_dump($c);
$c = 99;
try { preg_replace_callback('/x/', function($m) { throw new Exception("boom2"); }, 'xax', -1, $c); } catch (Exception $e) { echo "caught: ", $e->getMessage(), "\n"; }
var_dump($c);
$r = preg_replace_callback('/(\d+)/', fn($m) => $m[1] * 2, 'a1b22c333');
var_dump($r);
