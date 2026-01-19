<?php
$iterations = 10000;
$str = "Hello%20World%21%20Test%20%26%20Demo";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = rawurldecode($str);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";