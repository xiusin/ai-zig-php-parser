<?php
/**
 * Test arrow function in class - using parentheses to disambiguate
 */
class Test {
    public $fn;
    
    public function __construct() {
        $this->fn = fn() => 42;
    }
}

$obj = new Test();
// Use parentheses to access property first, then call
echo "Result: " . ($obj->fn)() . "\n";
