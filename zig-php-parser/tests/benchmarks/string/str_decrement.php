<?php
$iterations = 10000;
$str = "abc";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    // PHP 8.3+ str_decrement
    if (function_exists('str_decrement')) {
        $result = str_decrement($str);
    } else {
        // Fallback for older PHP
        $result = $str;
        $result--;
    }
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";