<?php
abstract class Animal {
    protected $name;
    
    public function __construct($name) {
        $this->name = $name;
    }
    
    abstract public function speak();
    abstract public function move();
    
    public function getName() {
        return $this->name;
    }
}

class Dog extends Animal {
    public function speak() {
        return "Woof!";
    }
    
    public function move() {
        return "Running";
    }
}

class Cat extends Animal {
    public function speak() {
        return "Meow!";
    }
    
    public function move() {
        return "Walking";
    }
}

$dog = new Dog("Buddy");
$cat = new Cat("Whiskers");

echo $dog->getName() . " says: " . $dog->speak() . "\n";
echo $dog->getName() . " is: " . $dog->move() . "\n";
echo $cat->getName() . " says: " . $cat->speak() . "\n";
echo $cat->getName() . " is: " . $cat->move() . "\n";
?>