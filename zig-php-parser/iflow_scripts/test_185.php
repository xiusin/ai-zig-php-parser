<?php

$arr = [1, 2, 2, 3, 3, 3];
$counts = array_count_values($arr);
echo $counts[2];
echo $counts[3];

?>
