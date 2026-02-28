<?php
$matrix = [[1, 2], [3, 4]];
echo "Matrix: ";
var_dump($matrix);
echo "\n";

foreach ($matrix as $row) {
    echo "Row: ";
    var_dump($row);
    echo "\n";
    
    foreach ($row as $val) {
        echo "Val: ";
        var_dump($val);
        echo "\n";
    }
}
?>
