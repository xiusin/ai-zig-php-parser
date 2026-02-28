<?php

function test($x = 5, $y = 10) {
    return $x + $y;
}
echo test() . test(2) . test(2, 3);

?>
