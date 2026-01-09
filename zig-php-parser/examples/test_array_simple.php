<?php

$arr = [1, 2, 3, 4, 5];
echo "Initial: " . json_encode($arr) . "\n";

$arr[] = 'a';
echo "After append a: " . json_encode($arr) . "\n";

$arr[] = 'b';
echo "After append b: " . json_encode($arr) . "\n";
