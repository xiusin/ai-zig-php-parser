<?php
// Foreach with function return test
function getArray() {
    return ["a", "b", "c"];
}

foreach (getArray() as $item) {
    echo "Item: {$item}\n";
}
echo "Done\n";
