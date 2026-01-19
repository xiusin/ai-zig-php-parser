<?php
$iterations = 10000;
$str1 = "Hello World";
$str2 = "Hello PHP";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = similar_text($str1, $str2);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";