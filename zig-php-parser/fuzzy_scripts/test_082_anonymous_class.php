<?php
// Test basic anonymous class
$obj = new class {
    public $name = "Anonymous";
    
    public function greet() {
        return "Hello from " . $this->name;
    }
};

echo $obj->greet() . "\n";
echo $obj->name . "\n";

// Test anonymous class with constructor args
$obj2 = new class("World") {
    public $greeting;
    
    public function __construct($name) {
        $this->greeting = "Hello, " . $name . "!";
    }
    
    public function getGreeting() {
        return $this->greeting;
    }
};

echo $obj2->getGreeting() . "\n";

// Test anonymous class with method
$calculator = new class {
    public function add($a, $b) {
        return $a + $b;
    }
    
    public function multiply($a, $b) {
        return $a * $b;
    }
};

echo "3 + 4 = " . $calculator->add(3, 4) . "\n";
echo "3 * 4 = " . $calculator->multiply(3, 4) . "\n";
?>
