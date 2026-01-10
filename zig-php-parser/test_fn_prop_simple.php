<?php
// Test accessing property named fn
class Test {
    public $fn = 123;
}

$obj = new Test();
echo $obj->fn . "\n";
