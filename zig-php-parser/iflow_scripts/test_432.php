<?php
function &getRef() { global $x; return $x; } $x = 100; $ref = &getRef(); $ref = 200; echo $x;?>
