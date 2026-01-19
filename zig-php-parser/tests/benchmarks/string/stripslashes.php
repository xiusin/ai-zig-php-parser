<?php
$iterations = 10000;
$str = "It\\'s a \\\"test\\\" string with \\\\ backslash";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = stripslashes($str);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";