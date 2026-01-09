<?php

class Test {
    public $value = 10;
}

function test($obj) {
    $y = 5;
    $fn = fn($x) => $x + $y;
    $result = $fn(5);
    return 10;
}

$t = new Test();
test($t);
echo "1 done\n";

test($t);
echo "2 done\n";

echo "Done\n";

