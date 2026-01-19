<?php
$iterations = 10000;
$haystack = "abcdef123";
$char_set = "0123456789";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = strcspn($haystack, $char_set);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";