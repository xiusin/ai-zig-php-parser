<?php
// 复杂场景测试 1: 嵌套类和继承

class Animal {
    protected string $name;
    protected int $age;
    
    public function __construct(string $name, int $age) {
        $this->name = $name;
        $this->age = $age;
    }
    
    public function speak(): string {
        return "Animal speaks";
    }
    
    public function getInfo(): string {
        return "Name: {$this->name}, Age: {$this->age}";
    }
}

class Dog extends Animal {
    private string $breed;
    
    public function __construct(string $name, int $age, string $breed) {
        parent::__construct($name, $age);
        $this->breed = $breed;
    }
    
    public function speak(): string {
        return "Woof! I'm {$this->name}";
    }
    
    public function getBreed(): string {
        return $this->breed;
    }
}

class Cat extends Animal {
    private bool $indoor;
    
    public function __construct(string $name, int $age, bool $indoor) {
        parent::__construct($name, $age);
        $this->indoor = $indoor;
    }
    
    public function speak(): string {
        return "Meow! I'm {$this->name}";
    }
    
    public function isIndoor(): bool {
        return $this->indoor;
    }
}

// 测试继承
$dog = new Dog("Buddy", 3, "Golden Retriever");
echo $dog->speak() . "\n";
echo $dog->getInfo() . "\n";
echo "Breed: " . $dog->getBreed() . "\n";

$cat = new Cat("Whiskers", 2, true);
echo $cat->speak() . "\n";
echo $cat->getInfo() . "\n";
echo "Indoor: " . ($cat->isIndoor() ? "yes" : "no") . "\n";

echo "\nTest 1 passed!\n";
