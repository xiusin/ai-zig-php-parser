<?php
$iterations = 10000;
$str = "Hello World! This is a test string with special chars: äöü";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = quoted_printable_encode($str);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";