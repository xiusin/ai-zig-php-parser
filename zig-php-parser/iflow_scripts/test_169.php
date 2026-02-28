<?php

$arr = [1, 2, 3, 4, 5];
foreach ($arr as &$v) {
    $v *= 2;
}
unset($v);
echo implode(",", $arr);

?>
