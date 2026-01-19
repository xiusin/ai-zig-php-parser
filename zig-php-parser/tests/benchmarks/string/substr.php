<?php
$iterations = 10000;
$str = "The quick brown fox jumps over the lazy dog";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = substr($str, 10, 15);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";