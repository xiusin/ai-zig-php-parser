<?php
$iterations = 10000;
$str = "abc";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    // PHP 8.3+ str_increment
    if (function_exists('str_increment')) {
        $result = str_increment($str);
    } else {
        // Fallback for older PHP
        $result = $str;
        $result++;
    }
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";