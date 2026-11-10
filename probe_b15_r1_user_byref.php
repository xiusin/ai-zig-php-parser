<?php
function byref(&$x) { var_dump($x); $x = 99; }
byref($undef);
echo "after: ";
var_dump($undef);
byref($undef2, $extra);
