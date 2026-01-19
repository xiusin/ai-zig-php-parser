<?php
$iterations = 10000;
$str1 = "kitten";
$str2 = "sitting";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = levenshtein($str1, $str2);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";