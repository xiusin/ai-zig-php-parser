<?php

$x = 1;
function modify() {
    global $x;
    $x = 100;
}
modify();
echo $x;

?>
