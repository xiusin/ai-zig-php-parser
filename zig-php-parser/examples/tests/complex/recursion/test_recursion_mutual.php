<?php
function isEven($n) {
    if ($n == 0) {
        return true;
    }
    return isOdd($n - 1);
}

function isOdd($n) {
    if ($n == 0) {
        return false;
    }
    return isEven($n - 1);
}

for ($i = 0; $i <= 20; $i++) {
    echo "$i is " . (isEven($i) ? "even" : "odd") . "\n";
}
