<?php

$i = 0;
$j = 0;
while ($i < 10) {
    $i++;
    $j += $i;
    if ($j > 20) break;
}
echo $i;
echo $j;

?>
