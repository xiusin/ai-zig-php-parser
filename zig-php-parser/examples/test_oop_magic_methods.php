<?php
// Magic methods testing
class MagicBox {
    private $data = [];
    private $name;
    
    public function __construct($name = "Box") {
        $this->name = $name;
        echo "Creating {$this->name}\n";
    }
    
    public function __destruct() {
        echo "Destroying {$this->name}\n";
    }
    
    public function __get($key) {
        echo "Getting undefined property: {$key}\n";
        return isset($this->data[$key]) ? $this->data[$key] : null;
    }
    
    public function __set($key, $value) {
        echo "Setting property: {$key} = {$value}\n";
        $this->data[$key] = $value;
    }
    
    public function __isset($key) {
        echo "Checking if property exists: {$key}\n";
        return isset($this->data[$key]);
    }
    
    public function __unset($key) {
        echo "Unsetting property: {$key}\n";
        unset($this->data[$key]);
    }
    
    public function __call($method, $arguments) {
        echo "Calling undefined method: {$method}\n";
        echo "Arguments: " . implode(", ", $arguments) . "\n";
        return "Magic method called";
    }
    
    public static function __callStatic($method, $arguments) {
        echo "Calling undefined static method: {$method}\n";
        echo "Arguments: " . implode(", ", $arguments) . "\n";
        return "Static magic method called";
    }
    
    public function __toString() {
        return "MagicBox(name={$this->name}, items=" . count($this->data) . ")";
    }
    
    public function __invoke($x, $y) {
        echo "Invoking MagicBox as function with args: {$x}, {$y}\n";
        return $x + $y;
    }
    
    public function __clone() {
        echo "Cloning MagicBox\n";
        $this->name = "Clone of " . $this->name;
    }
}

// Test magic methods
$box = new MagicBox("MyBox");

$box->item1 = "value1";
$box->item2 = "value2";

echo "item1: " . $box->item1 . "\n";
echo "item2: " . $box->item2 . "\n";

echo "isset item1: " . (isset($box->item1) ? "yes" : "no") . "\n";
echo "isset item3: " . (isset($box->item3) ? "yes" : "no") . "\n";

unset($box->item1);

echo "Calling magic method: " . $box->magicMethod("arg1", "arg2") . "\n";
echo "Calling static magic method: " . MagicBox::staticMagicMethod("arg3", "arg4") . "\n";

echo "String representation: " . $box . "\n";

echo "Invoking as function: " . $box(5, 10) . "\n";

$box2 = clone $box;
echo "Cloned box: " . $box2 . "\n";

// Trigger destructor
unset($box);
unset($box2);

echo "Done\n";
