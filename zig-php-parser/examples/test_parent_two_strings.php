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
    private string $city;
    
    public function __construct(string $name, string $job, string $city) {
        parent::__construct($name);
        $this->job = $job;
        $this->city = $city;
    }
    
    public function greet(): string {
        return parent::greet() . " I work as a {$this->job}.";
    }
}

$c = new Child("Charlie", "Engineer", "NYC");
echo $c->greet() . "\n";
?>
