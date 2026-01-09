<?php

$arr = [4, 5];
echo "Initial: " . json_encode($arr) . "\n";

$arr[] = 'a';
echo "After append 'a': " . json_encode($arr) . "\n";
