<?php

$arr = [];
for ($i = 0; $i < 5; $i++) {
    $arr[] = $i * 2;
}
echo count($arr) . implode(",", $arr);

?>
