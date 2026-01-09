<?php

$arr = [1, 2, 4, 5];
echo "Initial: " . json_encode($arr) . "\n";

$arr[] = 'X';
echo "After append X: " . json_encode($arr) . "\n";

$arr2 = [1, 2, 4, 5];
array_splice($arr2, 2, 0, ['a']);
echo "After splice(2,0,['a']): " . json_encode($arr2) . "\n";
