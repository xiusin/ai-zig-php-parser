<?php
$iterations = 10000;
$haystack = "The quick brown FOX jumps over the lazy fox";
$needle = "fox";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = strripos($haystack, $needle);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";