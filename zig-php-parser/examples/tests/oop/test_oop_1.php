<?php
// 继承测试
class Animal {
    protected $name;
    
    public function __construct($name) {
        $this->name = $name;
    }
    
    public function speak() {
        return $this->name . " makes a sound";
    }
}

class Dog extends Animal {
    public function speak() {
        return $this->name . " barks";
    }
}

$dog = new Dog("Buddy");
echo $dog->speak() . "\n";
?>