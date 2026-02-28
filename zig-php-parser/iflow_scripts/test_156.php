<?php

function deepRecursive($n) {
    if ($n <= 0) return 0;
    return $n + deepRecursive($n - 1);
}
echo deepRecursive(100);

?>
