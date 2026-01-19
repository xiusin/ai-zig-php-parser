<?php
$iterations = 10000;
$haystack = "The Quick Brown FOX Jumps Over The Lazy Dog";
$needle = "fox";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $pos = stripos($haystack, $needle);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";