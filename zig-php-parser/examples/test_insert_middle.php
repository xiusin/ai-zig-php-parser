<?php

$arr = [1, 2, 4, 5];
echo "Initial: " . json_encode($arr) . "\n";

// Manual insert at position 2
// 1. Insert at beginning
$arr2 = [];
$arr2[] = 1;
$arr2[] = 2;
$arr2[] = 'a';  // Insert at position 2
$arr2[] = 4;
$arr2[] = 5;
echo "Manual rebuild: " . json_encode($arr2) . "\n";
