<?php
function test() {
    $x = 5;
    if ($x > 0) {
        return 1;
    } else {
        return 0;
    }
}

$result = test();
if ($result) {
    echo "yes";
} else {
    echo "no";
}
