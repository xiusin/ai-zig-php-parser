<?php
$iterations = 10000;
$str = "Hello\\nWorld\\tTest\\r\\n";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = stripcslashes($str);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";