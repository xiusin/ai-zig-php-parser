<?php

$dict = ["a" => 1, "b" => 2, "c" => 3];
$sum = 0;
foreach ($dict as $k => $v) {
    $sum += $v;
}
echo $sum;

?>
