<?php

$assoc = ["a" => 1, "b" => 2, "c" => 3];
$sum = 0;
foreach ($assoc as $key => $value) {
    $sum += $value;
}
echo $sum;

?>
