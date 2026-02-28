<?php

function deepNested($n) {
    $result = 0;
    for ($i = 0; $i < $n; $i++) {
        for ($j = 0; $j < $n; $j++) {
            for ($k = 0; $k < $n; $k++) {
                $result += $i * $j + $k;
            }
        }
    }
    return $result;
}
echo deepNested(5);

?>
