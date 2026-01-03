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
    
    public function __construct(string $name, string $job) {
        parent::__construct($name);
        $this->job = $job;
    }
    
    public function greet(): string {
        $base = parent::greet();
        return $base . " I work as a {$this->job}.";
    }
}

$c = new Child("Charlie", "Engineer");
echo $c->greet() . "\n";
?>
