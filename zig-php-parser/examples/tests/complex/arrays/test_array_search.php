<?php
$array = ["apple", "banana", "cherry", "date", "banana"];

$pos = array_search("banana", $array);
echo "First banana at: $pos\n";

$pos = array_search("banana", $array, true);
echo "First banana (strict) at: $pos\n";

echo "Has mango: " . (in_array("mango", $array) ? "yes" : "no") . "\n";
echo "Has banana: " . (in_array("banana", $array) ? "yes" : "no") . "\n";
