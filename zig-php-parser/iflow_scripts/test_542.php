<?php
function f($n) { return $n <= 1 ? 1 : $n * f($n-1); } echo f(8);?>
