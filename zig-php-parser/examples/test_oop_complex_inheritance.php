<?php
// Complex inheritance chain with multiple levels
class Animal {
    protected $name;
    protected $age;
    
    public function __construct($name, $age) {
        $this->name = $name;
        $this->age = $age;
    }
    
    public function speak() {
        return "Animal sound";
    }
    
    public function getInfo() {
        return "Name: {$this->name}, Age: {$this->age}";
    }
}

class Mammal extends Animal {
    protected $furColor;
    
    public function __construct($name, $age, $furColor) {
        parent::__construct($name, $age);
        $this->furColor = $furColor;
    }
    
    public function breathe() {
        return "Breathing with lungs";
    }
}

class Dog extends Mammal {
    private $breed;
    
    public function __construct($name, $age, $furColor, $breed) {
        parent::__construct($name, $age, $furColor);
        $this->breed = $breed;
    }
    
    public function speak() {
        return "Woof! Woof!";
    }
    
    public function fetch() {
        return "Fetching the ball";
    }
    
    public function getFullInfo() {
        return parent::getInfo() . ", Fur: {$this->furColor}, Breed: {$this->breed}";
    }
}

class Cat extends Mammal {
    private $lives;
    
    public function __construct($name, $age, $furColor, $lives = 9) {
        parent::__construct($name, $age, $furColor);
        $this->lives = $lives;
    }
    
    public function speak() {
        return "Meow!";
    }
    
    public function climb() {
        return "Climbing a tree";
    }
}

// Test complex inheritance
$dog = new Dog("Buddy", 5, "brown", "Golden Retriever");
$cat = new Cat("Whiskers", 3, "white");

echo $dog->speak() . "\n";
echo $dog->breathe() . "\n";
echo $dog->fetch() . "\n";
echo $dog->getFullInfo() . "\n";

echo $cat->speak() . "\n";
echo $cat->breathe() . "\n";
echo $cat->climb() . "\n";
echo $cat->getInfo() . "\n";

echo "Done\n";
