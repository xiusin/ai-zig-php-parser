<?php

global $a, $b, $c;
$a = 1; $b = 2; $c = 3;
function test() {
    global $a, $b, $c;
    return $a + $b + $c;
}
echo test();

?>
