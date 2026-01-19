<?php
$iterations = 10000;
$str = "Line 1\nLine 2\nLine 3\nLine 4";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = nl2br($str);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";