<?php
$n = 400000;
$acc = 0;
for ($i = 0; $i < $n; $i++) {
    $acc += $i * 3 + 1;
}
echo $acc . "\n";
