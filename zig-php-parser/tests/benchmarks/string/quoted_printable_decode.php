<?php
$iterations = 10000;
$str = "Hello=20World=21=20This=20is=20a=20test";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = quoted_printable_decode($str);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";