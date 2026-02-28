<?php

$arr = [1, 2, 3, 4, 5];
for ($i = 0; $i < count($arr); $i++) {
    $arr[$i] *= 2;
}
echo implode(",", $arr);

?>
