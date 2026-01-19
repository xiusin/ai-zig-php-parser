<?php
$iterations = 10000;
$haystack = "The quick brown fox";
$replacement = "slow";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = substr_replace($haystack, $replacement, 4, 5);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";