<?php

class Test {
    public function test() {
        $fn = fn() => 1; // 创建闭包
        return $fn; // 返回闭包
    }
}

$t = new Test();
$result1 = $t->test();
echo "1 done\n";

$result2 = $t->test();
echo "2 done\n";

echo "Done\n";
