<?php
$iterations = 10000;
$str = "&lt;script&gt;alert(&quot;XSS&quot;);&lt;/script&gt;";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = html_entity_decode($str);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";