<?php
$iterations = 10000;
$str = "<script>alert('XSS');</script> & \"quotes\"";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = htmlspecialchars($str);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";