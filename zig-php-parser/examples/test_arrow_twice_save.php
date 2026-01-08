<?php

class Test {
    public function test() {
        $fn = fn() => 1;
        return $fn;
    }
}

$t = new Test();
$result1 = $t->test();
echo "1 done\n";
$result1(); // 调用闭包
echo "1 called\n";

$result2 = $t->test();
echo "2 done\n";
$result2(); // 调用闭包
echo "2 called\n";

echo "Done\n";