<?php
$iterations = 10000;
$haystack = "The quick brown fox";
$char_set = "aeiou";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = strpbrk($haystack, $char_set);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";