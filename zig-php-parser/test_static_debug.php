<?php
function &getRef() {
    echo "Before static\n";
    static $x = 10;
    echo "After static, x = $x\n";
    return $x;
}
echo "Calling getRef\n";
$ref = &getRef();
echo "Got ref: $ref\n";
?>
