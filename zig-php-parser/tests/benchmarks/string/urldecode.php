<?php
$iterations = 10000;
$str = "Hello+World%21+This+is+a+test+%26+demo.";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = urldecode($str);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";