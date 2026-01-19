<?php
$iterations = 10000;
$str = "Robert";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = soundex($str);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";