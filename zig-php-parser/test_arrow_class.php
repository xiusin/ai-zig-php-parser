<?php
/**
 * Test arrow function in class
 */
class Test {
    public $fn;
    
    public function __construct() {
        $this->fn = fn() => 42;
    }
}

$obj = new Test();
echo "Result: " . $obj->fn() . "\n";

