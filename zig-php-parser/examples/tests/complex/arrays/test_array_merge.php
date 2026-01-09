<?php
$arr1 = ["a", "b", "c"];
$arr2 = [1, 2, 3];

$merged = array_merge($arr1, $arr2);
echo "Merged: " . implode(", ", $merged) . "\n";

$keys = ["name", "age", "city"];
$values = ["John", 30, "NYC"];

$combined = array_combine($keys, $values);
echo "Combined: ";
print_r($combined);
