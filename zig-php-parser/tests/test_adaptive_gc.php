<?php
/**
 * Test script for Adaptive GC
 * This script creates memory pressure to trigger GC behavior
 */

echo "=== Adaptive GC Test ===\n\n";

// Test 1: Basic allocation
echo "Test 1: Basic allocation\n";
$arr = [];
for ($i = 0; $i < 1000; $i++) {
    $arr[] = "string_" . $i;
}
echo "Created array with " . count($arr) . " elements\n";

// Test 2: Object creation
echo "\nTest 2: Object creation\n";
class TestObject {
    public $data;
    public function __construct($d) {
        $this->data = $d;
    }
}

$objects = [];
for ($i = 0; $i < 500; $i++) {
    $objects[] = new TestObject("data_" . $i);
}
echo "Created " . count($objects) . " objects\n";

// Test 3: Nested arrays
echo "\nTest 3: Nested arrays\n";
$nested = [];
for ($i = 0; $i < 100; $i++) {
    $nested[] = [
        "id" => $i,
        "name" => "item_" . $i,
        "values" => [$i, $i + 1, $i + 2]
    ];
}
echo "Created " . count($nested) . " nested arrays\n";

// Test 4: String operations
echo "\nTest 4: String operations\n";
$str = "";
for ($i = 0; $i < 100; $i++) {
    $str = $str . "x";
}
echo "Created string of length " . strlen($str) . "\n";

// Test 5: Function calls with local allocations
echo "\nTest 5: Function calls\n";
function create_temp_data($n) {
    $temp = [];
    for ($i = 0; $i < $n; $i++) {
        $temp[] = $i * 2;
    }
    return count($temp);
}

$total = 0;
for ($i = 0; $i < 100; $i++) {
    $total = $total + create_temp_data(50);
}
echo "Total items processed: " . $total . "\n";

echo "\n=== Adaptive GC Test Complete ===\n";
?>
