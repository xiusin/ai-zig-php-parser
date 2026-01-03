<?php

for range 5 as $i {
    echo "Before: i = " . $i . "\n";
    if ($i == 2) {
        echo "Breaking at i = 2\n";
        break;
        echo "After break (should not print)\n";
    }
    echo "After if: i = " . $i . "\n";
}
echo "Loop ended\n";
