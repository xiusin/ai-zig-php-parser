<?php
$iterations = 10000;
$str = "Hello World Test String";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    // convert_cyr_string is deprecated, using simple copy
    $result = $str;
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";