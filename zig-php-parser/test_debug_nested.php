<?php
$matrix = [[1, 2]];
foreach ($matrix as $row) {
    echo "Outer loop\n";
    foreach ($row as $val) {
        echo "Inner loop: $val\n";
    }
}
?>
