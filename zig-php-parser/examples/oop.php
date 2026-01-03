<?php
// Object-Oriented Programming example

class Person {
    private string $name;
    private int $age;
    
    public function __construct(string $name, int $age) {
        $this->name = $name;
        $this->age = $age;
    }
    
    public function getName(): string {
        return $this->name;
    }
    
    public function getAge(): int {
        return $this->age;
    }
    
    public function greet(): string {
        return "Hello, I'm {$this->name} and I'm {$this->age} years old.";
    }
    
    public function haveBirthday(): void {
        $this->age++;
        echo "{$this->name} is now {$this->age} years old!\n";
    }
}

// Create instances
$alice = new Person("Alice", 30);
$bob = new Person("Bob", 25);

// Use methods
echo $alice->greet() . "\n";
echo $bob->greet() . "\n";

// Modify state
$alice->haveBirthday();
$bob->haveBirthday();

// Inheritance example
class Employee extends Person {
    private string $jobTitle;
    private float $salary;
    
    public function __construct(string $name, int $age, string $jobTitle, float $salary) {
        parent::__construct($name, $age);
        $this->jobTitle = $jobTitle;
        $this->salary = $salary;
    }
    
    public function getJobTitle(): string {
        return $this->jobTitle;
    }
    
    public function getSalary(): float {
        return $this->salary;
    }
    
    public function greet(): string {
        return parent::greet() . " I work as a {$this->jobTitle}.";
    }
}

$employee = new Employee("Charlie", 35, "Software Engineer", 75000.0);
echo $employee->greet() . "\n";
echo "Salary: $" . $employee->getSalary() . "\n";
?>