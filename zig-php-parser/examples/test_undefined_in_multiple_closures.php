<?php
// Test multiple closures with undefined variables
$closure1 = function() use ($undefined1) {
    return $undefined1;
};
$closure2 = function() use ($undefined2) {
    return $undefined2;
};
$closure3 = function() use ($undefined3) {
    return $undefined3;
};
$closure1();
$closure2();
$closure3();
echo "Done\n";
