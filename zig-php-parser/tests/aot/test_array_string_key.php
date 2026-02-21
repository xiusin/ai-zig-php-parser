<?php
$arr = [1, 2];
$arr["a"] = 3;
$arr["b"] = 4;
$sum = $arr["a"] + $arr["b"] + $arr[0];
echo "StrKey: $sum (expect 8)\n";
