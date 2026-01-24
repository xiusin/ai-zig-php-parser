<?php
function isPositive($x) {
    if ($x > 0) {
        return true;
    } else {
        return false;
    }
}

$result = isPositive(5);
if ($result) {
    echo "yes";
} else {
    echo "no";
}
