<?php
class MagicClass {
    private $data = array();
    
    public function __set($name, $value) {
        $this->data[$name] = $value;
        echo "Setting " . $name . " to " . $value . "\n";
    }
    
    public function __get($name) {
        if (array_key_exists($name, $this->data)) {
            return $this->data[$name];
        }
        return "Property " . $name . " not found";
    }
    
    public function __call($name, $arguments) {
        echo "Calling method " . $name . " with arguments: " . implode(", ", $arguments) . "\n";
        return "Method result";
    }
    
    public static function __callStatic($name, $arguments) {
        echo "Calling static method " . $name . "\n";
        return "Static method result";
    }
    
    public function __toString() {
        return "MagicClass instance";
    }
    
    public function __isset($name) {
        return isset($this->data[$name]);
    }
    
    public function __unset($name) {
        unset($this->data[$name]);
        echo "Unsetting " . $name . "\n";
    }
}

$obj = new MagicClass();
$obj->property1 = "value1";
$obj->property2 = "value2";

echo "property1: " . $obj->property1 . "\n";
echo "property2: " . $obj->property2 . "\n";
echo "undefined: " . $obj->undefined . "\n";

$obj->someMethod(1, 2, 3);
MagicClass::staticMethod();

echo "String representation: " . $obj . "\n";
echo "Isset property1: " . (isset($obj->property1) ? "Yes" : "No") . "\n";

unset($obj->property1);
echo "Isset property1 after unset: " . (isset($obj->property1) ? "Yes" : "No") . "\n";
?>