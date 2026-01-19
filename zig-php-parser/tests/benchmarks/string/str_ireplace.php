<?php
$iterations = 10000;
$haystack = "The quick brown FOX jumps over the lazy dog";
$search = "fox";
$replace = "cat";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = str_ireplace($search, $replace, $haystack);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";