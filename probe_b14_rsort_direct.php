<?php
$v = "s";
try { rsort($v); } catch (TypeError $e) { echo "direct caught: ", $e->getMessage(), "\n"; }
$fn = "rsort";
$v2 = "s";
try { $fn($v2); } catch (TypeError $e) { echo "varfn caught: ", $e->getMessage(), "\n"; }
echo "end\n";
