<?php

$arr = [1, 2, 3, 4, 5, 6];
$chunks = array_chunk($arr, 2);
echo count($chunks);
echo count($chunks[0]);

?>
