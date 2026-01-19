<?php
$iterations = 5000;
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $arr = array(1, 2, 3, 4, 5, 6, 7, 8, 9, 10);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";
