<?php
function increment(&$value, $by = 1) {
    $value += $by;
    return $value;
}

$x = 10;
increment($x);
echo "After increment: $x\n";
increment($x, 5);
echo "After increment by 5: $x\n";
