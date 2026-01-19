<?php
$iterations = 10000;
$str = "Hello World 25";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    sscanf($str, "%s %s %d", $word1, $word2, $num);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";