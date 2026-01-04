<?php
class Base {
    private string $name;
    
    public function __construct(string $name) {
        $this->name = $name;
    }
    
    public function greet(): string {
        return "Hello, {$this->name}";
    }
}

class Child extends Base {
    private string $job;
    private float $salary;
    
    public function __construct(string $name, string $job, float $salary) {
        parent::__construct($name);
        $this->job = $job;
        $this->salary = $salary;
    }
    
    public function greet(): string {
        return parent::greet() . " I work as a {$this->job}.";
    }
}

$c = new Child("Charlie", "Engineer", 75000.0);
echo $c->greet() . "\n";
?>
