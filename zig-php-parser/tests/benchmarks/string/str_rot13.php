<?php
$iterations = 10000;
$str = "The Quick Brown Fox";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = str_rot13($str);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";