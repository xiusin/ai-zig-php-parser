<?php
$iterations = 10000;
$str = "&lt;tag&gt; &amp; &quot;quotes&quot;";
$start = hrtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = htmlspecialchars_decode($str);
}
$end = hrtime(true);
echo "Time: " . (($end - $start) / 1000000) . " ms\n";