<?php

echo "Testing simple closure\n";

$square = function($x) {
    return $x * $x;
};

$result = $square(5);
echo "Result: " . $result . "\n";

?>
