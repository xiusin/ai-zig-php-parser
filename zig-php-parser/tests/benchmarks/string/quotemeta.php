<?php
$iterations = 10000;
$str = "Hello. World? Test* [abc] (def) {ghi}";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = quotemeta($str);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";