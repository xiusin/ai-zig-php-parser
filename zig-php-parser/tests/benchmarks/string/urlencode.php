<?php
$iterations = 10000;
$str = "Hello World! This is a test & demo.";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = urlencode($str);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";