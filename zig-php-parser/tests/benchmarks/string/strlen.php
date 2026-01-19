<?php
$iterations = 10000;
$str = "Hello, World! This is a test string for performance benchmarking.";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $len = strlen($str);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";