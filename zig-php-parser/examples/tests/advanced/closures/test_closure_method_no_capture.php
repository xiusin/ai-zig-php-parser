<?php

class Test {
    public function test() {
        $fn = fn($x) => $x + 5;
        return 10;
    }
}

$t = new Test();
$t->test();
echo "1 done\n";

$t->test();
echo "2 done\n";

echo "Done\n";

