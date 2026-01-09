<?php
function factorial($n) {
    if ($n <= 1) {
        return 1;
    }
    return $n * factorial($n - 1);
}

for ($i = 0; $i <= 10; $i++) {
    echo "factorial($i) = " . factorial($i) . "\n";
}
