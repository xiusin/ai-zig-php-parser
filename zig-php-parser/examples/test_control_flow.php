<?php
// Test if/else
$x = 10;
if ($x > 5) {
    echo "x is greater than 5\n";
} else {
    echo "x is less than or equal to 5\n";
}

// Test while loop
$i = 0;
while ($i < 3) {
    echo "Loop iteration: " . $i . "\n";
    $i = $i + 1;
}

// Test for loop
for ($j = 0; $j < 3; $j = $j + 1) {
    echo "For loop: " . $j . "\n";
}

echo "Control flow test complete\n";
?>
