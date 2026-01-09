<?php
// Deep inheritance testing
class BaseObject {
    protected $id;
    protected $created_at;
    
    public function __construct() {
        $this->id = uniqid();
        $this->created_at = time();
    }
    
    public function getId() {
        return $this->id;
    }
    
    public function getCreatedAt() {
        return $this->created_at;
    }
}

class Entity extends BaseObject {
    protected $name;
    protected $description;
    
    public function __construct($name, $description = '') {
        parent::__construct();
        $this->name = $name;
        $this->description = $description;
    }
    
    public function getName() {
        return $this->name;
    }
    
    public function getDescription() {
        return $this->description;
    }
    
    public function setName($name) {
        $this->name = $name;
    }
}

class Person extends Entity {
    protected $age;
    protected $email;
    
    public function __construct($name, $age, $email, $description = '') {
        parent::__construct($name, $description);
        $this->age = $age;
        $this->email = $email;
    }
    
    public function getAge() {
        return $this->age;
    }
    
    public function getEmail() {
        return $this->email;
    }
    
    public function setAge($age) {
        $this->age = $age;
    }
}

class Employee extends Person {
    protected $salary;
    protected $position;
    protected $department;
    
    public function __construct($name, $age, $email, $salary, $position, $department, $description = '') {
        parent::__construct($name, $age, $email, $description);
        $this->salary = $salary;
        $this->position = $position;
        $this->department = $department;
    }
    
    public function getSalary() {
        return $this->salary;
    }
    
    public function getPosition() {
        return $this->position;
    }
    
    public function getDepartment() {
        return $this->department;
    }
    
    public function giveRaise($percentage) {
        $this->salary *= (1 + $percentage / 100);
    }
    
    public function promote($newPosition, $raisePercentage = 10) {
        $this->position = $newPosition;
        $this->giveRaise($raisePercentage);
    }
}

class Manager extends Employee {
    protected $team = [];
    protected $level;
    
    public function __construct($name, $age, $email, $salary, $position, $department, $level, $description = '') {
        parent::__construct($name, $age, $email, $salary, $position, $department, $description);
        $this->level = $level;
    }
    
    public function addTeamMember(Employee $employee) {
        $this->team[] = $employee;
    }
    
    public function getTeam() {
        return $this->team;
    }
    
    public function getTeamSize() {
        return count($this->team);
    }
    
    public function getLevel() {
        return $this->level;
    }
    
    public function promote($newPosition, $raisePercentage = 15) {
        parent::promote($newPosition, $raisePercentage);
        $this->level += 1;
    }
}

class Director extends Manager {
    protected $division;
    protected $budget;
    
    public function __construct($name, $age, $email, $salary, $position, $department, $level, $division, $budget, $description = '') {
        parent::__construct($name, $age, $email, $salary, $position, $department, $level, $description);
        $this->division = $division;
        $this->budget = $budget;
    }
    
    public function getDivision() {
        return $this->division;
    }
    
    public function getBudget() {
        return $this->budget;
    }
    
    public function setBudget($budget) {
        $this->budget = $budget;
    }
    
    public function approveExpense($amount) {
        if ($amount <= $this->budget) {
            $this->budget -= $amount;
            return true;
        }
        return false;
    }
}

// Test deep inheritance
echo "=== Deep Inheritance Testing ===\n";

$director = new Director(
    "Alice Smith",
    45,
    "alice@example.com",
    150000,
    "Director",
    "Engineering",
    4,
    "R&D",
    1000000,
    "Senior Director"
);

echo "Director: {$director->getName()}\n";
echo "ID: {$director->getId()}\n";
echo "Age: {$director->getAge()}\n";
echo "Email: {$director->getEmail()}\n";
echo "Salary: \${$director->getSalary()}\n";
echo "Position: {$director->getPosition()}\n";
echo "Department: {$director->getDepartment()}\n";
echo "Level: {$director->getLevel()}\n";
echo "Division: {$director->getDivision()}\n";
echo "Budget: \${$director->getBudget()}\n";
echo "Created: " . date('Y-m-d H:i:s', $director->getCreatedAt()) . "\n";

// Add team members
$engineer1 = new Employee("Bob Johnson", 30, "bob@example.com", 80000, "Engineer", "Engineering");
$engineer2 = new Employee("Carol White", 28, "carol@example.com", 85000, "Engineer", "Engineering");

$director->addTeamMember($engineer1);
$director->addTeamMember($engineer2);

echo "\nTeam size: {$director->getTeamSize()}\n";
echo "Team members:\n";
foreach ($director->getTeam() as $member) {
    echo "  - {$member->getName()} ({$member->getPosition()})\n";
}

// Test promotion
echo "\nPromoting director...\n";
$director->promote("VP of Engineering");
echo "New position: {$director->getPosition()}\n";
echo "New salary: \${$director->getSalary()}\n";
echo "New level: {$director->getLevel()}\n";

// Test expense approval
echo "\nApproving expenses...\n";
echo "Approve \$50000: " . ($director->approveExpense(50000) ? "Approved" : "Rejected") . "\n";
echo "Budget remaining: \${$director->getBudget()}\n";
echo "Approve \$200000: " . ($director->approveExpense(200000) ? "Approved" : "Rejected") . "\n";
echo "Budget remaining: \${$director->getBudget()}\n";

echo "\nDone\n";
