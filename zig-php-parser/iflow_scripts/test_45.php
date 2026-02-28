<?php

function sideEffect() {
    echo "called";
    return true;
}
$result = false && sideEffect();
echo $result ? "true" : "false";
$result = true || sideEffect();
echo $result ? "true" : "false";

?>
