<?php
$iterations = 10000;
$str = "Hello\nWorld\tTest\r\n";
$charlist = "\n\r\t";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = addcslashes($str, $charlist);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";