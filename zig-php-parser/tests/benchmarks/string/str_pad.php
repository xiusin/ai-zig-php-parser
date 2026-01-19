<?php
$iterations = 10000;
$str = "Hello";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = str_pad($str, 20, ' ', STR_PAD_RIGHT);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";