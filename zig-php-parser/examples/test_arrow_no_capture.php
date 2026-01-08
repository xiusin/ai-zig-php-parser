<?php

class Test {
    public $value = 10;

    public function test() {
        $y = 5;
        $fn = fn($x) => $x + $y;
        $result = $fn(5);
        echo "result = $result\n";
        return $result;
    }
}

$t = new Test();
$t->test();
echo "1 done\n";

$t->test();
echo "2 done\n";

echo "Done\n";
