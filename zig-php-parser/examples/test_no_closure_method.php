<?php

class Test {
    public function test() {
        // 不创建闭包，直接返回
        return 10;
    }
}

$t = new Test();
$t->test();
echo "1 done\n";

$t->test();
echo "2 done\n";

echo "Done\n";

