<?php
/**
 * Simple AOT Control Flow Test
 */

echo "=== Simple If/Else Test ===\n";

$x = 10;
if ($x > 0) {
    echo "x is positive\n";
} else {
    echo "x is not positive\n";
}

echo "After if/else\n";

echo "\n=== Simple While Loop Test ===\n";

$count = 3;
echo "Countdown: ";
while ($count > 0) {
    echo $count . " ";
    $count = $count - 1;
}
echo "\n";

echo "After while loop\n";

echo "\n=== Simple For Loop Test ===\n";

echo "Numbers: ";
for ($i = 1; $i <= 3; $i++) {
    echo $i . " ";
}
echo "\n";

echo "After for loop\n";

echo "\n=== Done ===\n";
