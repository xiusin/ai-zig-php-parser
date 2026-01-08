<?php

class Test {
    public function test() {
        $fn = fn() => 1; // 创建闭包
        return $fn;
    }
}

$global_fn = null;

class Test2 {
    public function test() {
        global $global_fn;
        $fn = fn() => 1;
        $global_fn = $fn; // 存储到全局变量
        return 10;
    }
}

$t = new Test();
$result1 = $t->test();
echo "1 done\n";

$t2 = new Test2();
$t2->test();
echo "2 done\n";

echo "Done\n";
