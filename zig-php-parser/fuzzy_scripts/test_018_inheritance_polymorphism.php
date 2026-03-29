<?php
// 测试18: 继承与多态深度测试
abstract class Animal {
    protected string $name;
    protected int $age;
    
    public function __construct(string $name, int $age) {
        $this->name = $name;
        $this->age = $age;
    }
    
    abstract public function speak(): string;
    abstract public function move(): string;
    
    public function getInfo(): string {
        return "{$this->name} is {$this->age} years old";
    }
}

interface Swimmable {
    public function swim(): string;
}

interface Flyable {
    public function fly(): string;
}

class Dog extends Animal {
    private string $breed;
    
    public function __construct(string $name, int $age, string $breed) {
        parent::__construct($name, $age);
        $this->breed = $breed;
    }
    
    public function speak(): string {
        return "Woof!";
    }
    
    public function move(): string {
        return "Running on 4 legs";
    }
    
    public function getBreed(): string {
        return $this->breed;
    }
}

class Cat extends Animal {
    private bool $isIndoor;
    
    public function __construct(string $name, int $age, bool $isIndoor) {
        parent::__construct($name, $age);
        $this->isIndoor = $isIndoor;
    }
    
    public function speak(): string {
        return "Meow!";
    }
    
    public function move(): string {
        return "Sneaking silently";
    }
    
    public function isIndoor(): bool {
        return $this->isIndoor;
    }
}

class Duck extends Animal implements Swimmable, Flyable {
    private string $color;
    
    public function __construct(string $name, int $age, string $color) {
        parent::__construct($name, $age);
        $this->color = $color;
    }
    
    public function speak(): string {
        return "Quack!";
    }
    
    public function move(): string {
        return "Waddling";
    }
    
    public function swim(): string {
        return "Swimming gracefully";
    }
    
    public function fly(): string {
        return "Flying south";
    }
}

// 测试多态
$animals = [
    new Dog("Buddy", 3, "Golden Retriever"),
    new Cat("Whiskers", 2, true),
    new Duck("Donald", 5, "White")
];

foreach ($animals as $animal) {
    echo $animal->getInfo() . "\n";
    echo "  Says: " . $animal->speak() . "\n";
    echo "  Moves: " . $animal->move() . "\n";
    
    if ($animal instanceof Swimmable) {
        echo "  Swims: " . $animal->swim() . "\n";
    }
    if ($animal instanceof Flyable) {
        echo "  Flies: " . $animal->fly() . "\n";
    }
}

// 类型检查
$dog = $animals[0];
echo "Is Animal: " . ($dog instanceof Animal ? "yes" : "no") . "\n";
echo "Is Dog: " . ($dog instanceof Dog ? "yes" : "no") . "\n";
echo "Is Cat: " . ($dog instanceof Cat ? "yes" : "no") . "\n";
?>
