<?php
$iterations = 10000;
$haystack = "The quick brown fox jumps over the lazy fox";
$needle = 'f';
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = strrchr($haystack, $needle);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";