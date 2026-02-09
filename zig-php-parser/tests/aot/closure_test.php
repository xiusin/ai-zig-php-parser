<?php

function createAdder(int $x): callable {
    return function(int $y) use ($x): int {
        return $x + $y;
    };
}

$add5 = createAdder(5);
$result = $add5(10);
echo "Result: $result\n";
