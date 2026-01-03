<?php
class Base {
    private $name;
    
    public function __construct($n) {
        $this->name = $n;
    }
    
    public function greet() {
        return "Hello, " . $this->name;
    }
}

class Child extends Base {
    public function __construct($n) {
        parent::__construct($n);
    }
    
    public function greet() {
        return parent::greet() . "!";
    }
}

$c = new Child("World");
echo $c->greet() . "\n";
?>
