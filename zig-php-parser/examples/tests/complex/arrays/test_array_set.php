<?php
$a = [1, 2, 3, 4, 5];
$b = [3, 4, 5, 6, 7];

echo "A: " . implode(", ", $a) . "\n";
echo "B: " . implode(", ", $b) . "\n";
echo "Intersection: " . implode(", ", array_intersect($a, $b)) . "\n";
echo "Union: " . implode(", ", array_unique(array_merge($a, $b))) . "\n";
echo "A - B: " . implode(", ", array_diff($a, $b)) . "\n";
echo "B - A: " . implode(", ", array_diff($b, $a)) . "\n";
echo "XOR: " . implode(", ", array_diff(array_merge($a, $b), array_intersect($a, $b))) . "\n";
