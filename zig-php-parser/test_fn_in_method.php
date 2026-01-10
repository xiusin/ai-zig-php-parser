<?php
// Test arrow function in method
class Test {
    public function test() {
        $fn = fn() => 42;
        return $fn();
    }
}

$obj = new Test();
echo $obj->test() . "\n";
