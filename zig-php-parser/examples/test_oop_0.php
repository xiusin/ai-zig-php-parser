<?php
// 类和对象测试
class Person {
    private $name;
    private $age;
    
    public function __construct($name, $age) {
        $this->name = $name;
        $this->age = $age;
    }
    
    public function getName() {
        return $this->name;
    }
    
    public function getAge() {
        return $this->age;
    }
    
    public function greet() {
        return "Hello, I'm " . $this->name . " and I'm " . $this->age . " years old.";
    }
}

$person = new Person("Alice", 30);
echo $person->greet() . "\n";
echo "Name: " . $person->getName() . "\n";
echo "Age: " . $person->getAge() . "\n";
?>