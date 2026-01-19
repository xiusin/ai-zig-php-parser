<?php
$iterations = 10000;
$start = hrtime(true);
ob_start();
for ($i = 0; $i < $iterations; $i++) {
    printf("Hello %s, you are %d years old", "World", 25);
}
ob_end_clean();
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";