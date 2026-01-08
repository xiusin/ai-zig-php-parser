<?php

class Test {
    public function test() {
        $fn = fn() => 1;
        return 10;
    }
}

$t = new Test();
echo "Before first call\n";
$t->test();
echo "After first call, before second call\n";
$t->test();
echo "After second call\n";

echo "Done\n";