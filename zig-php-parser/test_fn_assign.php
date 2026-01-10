<?php
// Test arrow function assignment to property
class Test {
    public $fn;

    public function test() {
        $this->fn = fn() => 42;
        return $this->fn();
    }
}

$obj = new Test();
echo $obj->test() . "\n";

