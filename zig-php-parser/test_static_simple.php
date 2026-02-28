<?php
function test() {
    static $x = 10;
    echo "x = $x\n";
    $x++;
}
test();
test();
test();
?>
