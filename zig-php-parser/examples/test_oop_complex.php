<?php
// OOP测试 - 继承、接口、多态

interface Pet {
    public function beFriendly(): string;
    public function play(): string;
}

class Dog implements Pet {
    public string $name;
    protected int $age;
    private string $breed;
    
    public function __construct(string $name, int $age, string $breed) {
        $this->name = $name;
        $this->age = $age;
        $this->breed = $breed;
    }
    
    public function makeSound(): string {
        return "Woof!";
    }
    
    public function beFriendly(): string {
        return $this->name . " wags tail";
    }
    
    public function play(): string {
        return $this->name . " fetches the ball";
    }
    
    public function getInfo(): string {
        return $this->name . ", " . $this->age . " years old, " . $this->breed;
    }
    
    public function getAge(): int {
        return $this->age;
    }
    
    public function setAge(int $age): void {
        $this->age = $age;
    }
}

class Cat implements Pet {
    public string $name;
    protected int $age;
    
    public function __construct(string $name, int $age) {
        $this->name = $name;
        $this->age = $age;
    }
    
    public function makeSound(): string {
        return "Meow!";
    }
    
    public function beFriendly(): string {
        return $this->name . " purrs";
    }
    
    public function play(): string {
        return $this->name . " chases laser pointer";
    }
    
    public function getInfo(): string {
        return $this->name . ", " . $this->age . " years old";
    }
}

// 多态函数
function handlePet(Pet $pet): string {
    return $pet->beFriendly() . " and " . $pet->play();
}

// 测试
$dog = new Dog("Buddy", 3, "Golden Retriever");
$cat = new Cat("Whiskers", 5);

echo "=== 对象创建 ===" . "\n";
echo "Dog: " . $dog->getInfo() . "\n";
echo "Cat: " . $cat->getInfo() . "\n";

echo "=== 接口调用 ===" . "\n";
echo "Dog says: " . $dog->makeSound() . "\n";
echo "Cat says: " . $cat->makeSound() . "\n";
echo handlePet($dog) . "\n";
echo handlePet($cat) . "\n";

echo "=== 方法链 ===" . "\n";
$dog->setAge(4);
$dog->setAge(5);
echo "Dog age: " . $dog->getAge() . "\n";

echo "=== 闭包捕获对象 ===" . "\n";
$getDogInfo = function() use ($dog) {
    return $dog->getInfo();
};
echo $getDogInfo() . "\n";

echo "=== 完成 ===" . "\n";
?>