<?php
class Base {
    private string $name;
    private int $age;
    
    public function __construct(string $name, int $age) {
        $this->name = $name;
        $this->age = $age;
    }
    
    public function greet(): string {
        return "Hello, I'm {$this->name} and I'm {$this->age} years old.";
    }
}

class Child extends Base {
    private string $job;
    
    public function __construct(string $name, int $age, string $job) {
        parent::__construct($name, $age);
        $this->job = $job;
    }
    
    public function greet(): string {
        return parent::greet() . " I work as a {$this->job}.";
    }
}

$c = new Child("Charlie", 35, "Engineer");
echo $c->greet() . "\n";
?>
