<?php
function f() { throw new Exception("direct"); }
function g() { f(); }
try { g(); } catch (Exception $e) { echo "caught: ", $e->getMessage(), "\n"; }
echo "after\n";
