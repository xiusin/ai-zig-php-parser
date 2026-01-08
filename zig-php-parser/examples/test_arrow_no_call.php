<?php

class Test {
    public function test() {
        $fn = fn() => 1; // 只创建闭包，不调用
        return 10;
    }
}

$t = new Test();
$t->test();
echo "1 done\n";

$t->test();
echo "2 done\n";

echo "Done\n";

