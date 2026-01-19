<?php
$iterations = 10000;
$format = "Hello %s, you are %d years old";
$args = ["World", 25];
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = vsprintf($format, $args);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";