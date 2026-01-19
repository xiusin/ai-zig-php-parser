<?php
$iterations = 10000;
$str = "name=John&age=25&city=NewYork";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    parse_str($str, $result);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";