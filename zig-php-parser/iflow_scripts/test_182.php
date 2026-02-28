<?php

$arr = [1, 2, 3, 4, 5];
array_splice($arr, 1, 2, [10, 20]);
echo implode(",", $arr);

?>
