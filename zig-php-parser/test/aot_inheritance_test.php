<?php
// 测试继承

class Animal {
    protected $name;
    protected $age;
    
    public function __construct($name, $age) {
        $this->name = $name;
        $this->age = $age;
    }
    
    public function getInfo() {
        return $this->name . " is " . $this->age . " years old";
    }
}

class Dog extends Animal {
    private $breed;
    
    public function __construct($name, $age, $breed) {
        parent::__construct($name, $age);
        $this->breed = $breed;
    }
    
    public function speak() {
        return "Woof! I'm " . $this->name;
    }
    
    public function getBreed() {
        return $this->breed;
    }
}

echo "=== 测试继承 ===\n";
$dog = new Dog("Buddy", 3, "Golden Retriever");
echo $dog->speak() . "\n";
echo $dog->getInfo() . "\n";
echo "Breed: " . $dog->getBreed() . "\n";
