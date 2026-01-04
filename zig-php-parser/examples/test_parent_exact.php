<?php
class Person {
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

class Employee extends Person {
    private string $jobTitle;
    private float $salary;
    
    public function __construct(string $name, int $age, string $jobTitle, float $salary) {
        parent::__construct($name, $age);
        $this->jobTitle = $jobTitle;
        $this->salary = $salary;
    }
    
    public function greet(): string {
        return parent::greet() . " I work as a {$this->jobTitle}.";
    }
}

$employee = new Employee("Charlie", 35, "Software Engineer", 75000.0);
echo $employee->greet() . "\n";
?>
