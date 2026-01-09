<?php
function createLargeArray($size) {
    $arr = array();
    for ($i = 0; $i < $size; $i++) {
        $arr[] = array(
            "id" => $i,
            "value" => "value_" . $i,
            "data" => str_repeat("x", 100)
        );
    }
    return $arr;
}

echo "Creating large array (10000 elements)\n";
$largeArray = createLargeArray(10000);
echo "Array created, count: " . count($largeArray) . "\n";

echo "First element ID: " . $largeArray[0]["id"] . "\n";
echo "Last element ID: " . $largeArray[count($largeArray) - 1]["id"] . "\n";

echo "Clearing array\n";
unset($largeArray);
echo "Array cleared\n";
?>