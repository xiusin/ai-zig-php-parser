<?php
$iterations = 10000;
$str = "The quick brown fox jumps over the lazy dog and runs away";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = wordwrap($str, 20);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";