<?php
$iterations = 10000;
$haystack = "The quick brown fox";
$needle = "fox";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = str_ends_with($haystack, $needle);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";