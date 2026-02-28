<?php
function counter() { static \$c = 0; \$c++; return \$c; } echo counter(); echo counter();
?>
