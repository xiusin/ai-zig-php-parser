<?php
// Return closure from function
function createGetter() {
    return function() { return 99; };
}
$getter = createGetter();
echo "getter(): " . $getter() . "\n";
?>
