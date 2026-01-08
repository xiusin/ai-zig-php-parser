<?php

function test() {
    $y = 5;
    $fn = fn($x) => $x + $y;
    return 10;
}

test();
echo "1 done\n";

test();
echo "2 done\n";

echo "Done\n";

