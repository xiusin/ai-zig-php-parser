<?php

class Test {
    public $value = 10;

    public function test() {
        $fn = fn($x) => $x + $this->value;
        $result = $fn(5);
        echo "result = $result\n";
        return $result;
    }
}

$t = new Test();
$t->test();
echo "1 done\n";

echo "About to call test() again...\n";
$t->test();
echo "2 done\n";

echo "Done\n";
