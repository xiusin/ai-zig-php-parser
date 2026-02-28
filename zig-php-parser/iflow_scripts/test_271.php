<?php
\$x = 1; function test() { global \$x; \$x = 100; } test(); echo \$x;
?>
