<?php
$iterations = 10000;
$haystack = "The quick brown fox";
$needle = "The";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = str_starts_with($haystack, $needle);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";