<?php
/**
 * Test arrow function - simplified
 */
class Test {
    public $fn;
    
    public function __construct() {
        $this->fn = fn() => 42;
    }
}

$obj = new Test();
$fn = $obj->fn;
echo "Result: " . $fn() . "\n";

