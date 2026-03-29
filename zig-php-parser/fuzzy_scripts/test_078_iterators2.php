<?php
// Test 078: ArrayObject, ArrayIterator
$ao = new ArrayObject(['x' => 10, 'y' => 20, 'z' => 30]);
echo "=== ArrayObject ===\n";
echo "Count: " . $ao->count() . "\n";
echo "ao['x']: " . $ao['x'] . "\n";

$ao['x'] = 100;
$ao['new'] = 999;
echo "After modify: ao['x']=" . $ao['x'] . ", ao['new']=" . $ao['new'] . "\n";

echo "\n=== ArrayIterator ===\n";
$ai = new ArrayIterator(['a' => 1, 'b' => 2, 'c' => 3]);
foreach ($ai as $k => $v) {
    echo "  $k => $v\n";
}

echo "\n=== Seek ===\n";
$ai->seek(1);
echo "Seek to 1: " . $ai->current() . "\n";

echo "\n=== RecursiveArrayIterator ===\n";
$nested = ['a' => 1, 'b' => ['c' => 2, 'd' => 3]];
$rai = new RecursiveArrayIterator($nested);
$rit = new RecursiveIteratorIterator($rai);

foreach ($rit as $key => $value) {
    echo "  depth=" . $rit->getDepth() . ": $key => $value\n";
}

echo "\n=== AppendIterator ===\n";
$first = new ArrayIterator([1, 2, 3]);
$second = new ArrayIterator([4, 5, 6]);
$append = new AppendIterator();
$append->append($first);
$append->append($second);

foreach ($append as $v) {
    echo "  $v\n";
}

echo "\n=== LimitIterator ===\n";
$base = new ArrayIterator(range(1, 10));
$limit = new LimitIterator($base, 2, 5);
foreach ($limit as $v) {
    echo "  $v\n";
}