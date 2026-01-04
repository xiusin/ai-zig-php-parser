<?php
// Test multiple undefined variables in array initialization
$arr = [
    $undefined1,
    $undefined2,
    $undefined3,
    "defined"
];
echo "Done\n";
