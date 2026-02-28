<?php

global $counter;
$counter = 0;
function increment() {
    global $counter;
    $counter++;
    return $counter;
}
for ($i = 0; $i < 5; $i++) {
    echo increment();
}

?>
