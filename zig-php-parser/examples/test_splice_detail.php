<?php

// Test splice step by step
$arr = [1, 2, 3, 4, 5];
echo "Initial: " . json_encode($arr) . "\n";

// Manually do what array_splice does
$removed = [];
for ($i = 2; $i < 3; $i++) {
    $removed[] = $arr[$i];
}
echo "Removed: " . json_encode($removed) . "\n";

// Rebuild array without removed elements
$new_arr = [];
foreach ($arr as $k => $v) {
    if ($k < 2 || $k >= 3) {
        $new_arr[] = $v;
    }
}
echo "After remove: " . json_encode($new_arr) . "\n";

// Insert replacement
$insert_arr = ['a', 'b'];
$result = [];
$insert_pos = 2;
$ri = 0;
for ($i = 0; $i < count($new_arr) + count($insert_arr); $i++) {
    if ($i >= $insert_pos && $i < $insert_pos + count($insert_arr)) {
        $result[] = $insert_arr[$ri++];
    } else {
        $result[] = $new_arr[$i - count($insert_arr)];
    }
}
echo "After insert: " . json_encode($result) . "\n";
