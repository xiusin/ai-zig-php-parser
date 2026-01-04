<?php
class Base {
    private string $name;
    
    public function __construct(string $name) {
        $this->name = $name;
    }
    
    public function greet(): string {
        return "Hello, " . $this->name;
    }
}

class Child extends Base {
    public function __construct(string $name) {
        parent::__construct($name);
    }
    
    public function greet(): string {
        return parent::greet() . "!";
    }
}

$c = new Child("World");
echo $c->greet() . "\n";
?>
