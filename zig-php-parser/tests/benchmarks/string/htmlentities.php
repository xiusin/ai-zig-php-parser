<?php
$iterations = 10000;
$str = "Café & Résumé <tag>";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = htmlentities($str);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";