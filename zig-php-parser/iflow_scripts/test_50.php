<?php

function &getRef() {
    static $x = 10;
    return $x;
}
$ref = &getRef();
$ref = 20;
echo getRef();

?>
