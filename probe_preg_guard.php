<?php
$m = ['old'];
try { preg_match('/x/', 'x', $m, 999999); } catch (ValueError $e) { echo "caught: ", $e->getMessage(), "\n"; }
var_dump($m);
$m2 = ['old'];
try { preg_match_all('/x/', 'x', $m2, 999999); } catch (ValueError $e) { echo "caught: ", $e->getMessage(), "\n"; }
var_dump($m2);
