<?php
// Test reference parameters

function increment(int &$value): void {
    $value++;
}

$counter = 10;
increment($counter);
echo "Counter after increment: {$counter}\n";

$counter = 20;
increment($counter);
echo "Counter after second increment: {$counter}\n";
?>
