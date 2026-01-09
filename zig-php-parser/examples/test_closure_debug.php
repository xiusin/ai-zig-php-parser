<?php
// Debug closure test
echo "Step 1: Create outer closure\n";
$createFn = function() {
    echo "Step 2: Inside outer closure\n";
    return function() {
        echo "Step 4: Inside inner closure\n";
        return 200;
    };
};
echo "Step 3: Call outer closure\n";
$innerFn = $createFn();
echo "Step 5: Call inner closure\n";
$result = $innerFn();
echo "Step 6: Result = " . $result . "\n";
?>
