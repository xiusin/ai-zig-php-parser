<?php
$result = "";
$i = 0;
while ($i < 1000) {
    $result = $result . "x";
    $i = $i + 1;
}
echo "Completed 1000 iterations\n";
echo "Length: ";
echo strlen($result);
echo "\n";
