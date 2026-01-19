<?php
$iterations = 10000;
$str = "John,Doe,25,New York,Engineer";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = str_getcsv($str);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";