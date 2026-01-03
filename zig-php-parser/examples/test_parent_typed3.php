<?php
class Base {
    private string $name;
    private int $age;
    
    public function __construct(string $name, int $age) {
        $this->name = $name;
        $this->age = $age;
    }
    
    public function greet(): string {
        return "Hello, I'm " . $this->name . " and I'm " . $this->age . " years old.";
    }
}

class Child extends Base {
    public function __construct(string $name, int $age) {
        parent::__construct($name, $age);
    }
    
    public function greet(): string {
        return parent::greet() . " Nice!";
    }
}

$c = new Child("Charlie", 35);
echo $c->greet() . "\n";
?>
