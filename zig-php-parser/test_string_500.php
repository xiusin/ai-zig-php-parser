<?php
$result = "";
$i = 0;
while ($i < 500) {
    $result = $result . "x";
    $i = $i + 1;
}
echo "Completed 500 iterations\n";
echo "Length: ";
echo strlen($result);
echo "\n";
