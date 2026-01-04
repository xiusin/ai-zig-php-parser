<?php

echo "Step 1: Define closure\n";

$test = function($x) {
    echo "Inside closure, x = " . $x . "\n";
    return $x * 2;
};

echo "Step 2: Call closure\n";
$result = $test(10);
echo "Step 3: Result = " . $result . "\n";

?>
