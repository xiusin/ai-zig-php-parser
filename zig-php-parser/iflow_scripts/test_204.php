<?php

function sumArray($arr) {
    $sum = 0;
    foreach ($arr as $v) {
        if (is_array($v)) {
            $sum += sumArray($v);
        } else {
            $sum += $v;
        }
    }
    return $sum;
}
$arr = [1, [2, 3], [4, [5, 6]]];
echo sumArray($arr);

?>
