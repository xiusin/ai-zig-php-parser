<?php
function getRef() {
    static $x = 10;
    return $x;
}
$val = getRef();
echo "val = $val\n";
$val = 20;
echo "After set, getRef = " . getRef() . "\n";
?>
