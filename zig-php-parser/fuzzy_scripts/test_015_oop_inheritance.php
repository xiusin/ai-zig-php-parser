<?php
// OOP继承测试

// 基类
class Animal {
    protected string $name;
    protected int $age;

    public function __construct(string $name, int $age) {
        $this->name = $name;
        $this->age = $age;
    }

    public function getName(): string {
        return $this->name;
    }

    public function speak(): string {
        return "Some sound";
    }

    public function info(): string {
        return "Animal: {$this->name}, age: {$this->age}";
    }
}

// 子类
class Dog extends Animal {
    private string $breed;

    public function __construct(string $name, int $age, string $breed) {
        parent::__construct($name, $age);
        $this->breed = $breed;
    }

    public function speak(): string {
        return "Woof!";
    }

    public function getBreed(): string {
        return $this->breed;
    }

    public function info(): string {
        return parent::info() . ", breed: {$this->breed}";
    }
}

// 另一个子类
class Cat extends Animal {
    public function speak(): string {
        return "Meow!";
    }
}

// 创建实例
$dog = new Dog('Buddy', 3, 'Golden Retriever');
$cat = new Cat('Whiskers', 2);

echo "Dog name: " . $dog->getName() . "\n";
echo "Dog breed: " . $dog->getBreed() . "\n";
echo "Dog speak: " . $dog->speak() . "\n";
echo "Dog info: " . $dog->info() . "\n";

echo "Cat name: " . $cat->getName() . "\n";
echo "Cat speak: " . $cat->speak() . "\n";

// instanceof多级检查
echo "dog instanceof Dog: " . var_export($dog instanceof Dog, true) . "\n";
echo "dog instanceof Animal: " . var_export($dog instanceof Animal, true) . "\n";

// 抽象类
abstract class Shape {
    abstract public function area(): float;
    abstract public function perimeter(): float;

    public function describe(): string {
        return "Area: {$this->area()}, Perimeter: {$this->perimeter()}";
    }
}

class Rectangle extends Shape {
    public function __construct(
        private float $width,
        private float $height
    ) {}

    public function area(): float {
        return $this->width * $this->height;
    }

    public function perimeter(): float {
        return 2 * ($this->width + $this->height);
    }
}

class Circle extends Shape {
    public function __construct(
        private float $radius
    ) {}

    public function area(): float {
        return 3.14159 * $this->radius * $this->radius;
    }

    public function perimeter(): float {
        return 2 * 3.14159 * $this->radius;
    }
}

$rect = new Rectangle(5, 3);
$circle = new Circle(2);

echo "Rectangle: " . $rect->describe() . "\n";
echo "Circle: " . $circle->describe() . "\n";

// final类和方法
final class FinalClass {
    public function method(): string {
        return "Cannot be overridden";
    }
}

// final方法
class BaseWithFinal {
    final public function cannotOverride(): string {
        return "This cannot be overridden";
    }

    public function canOverride(): string {
        return "This can be overridden";
    }
}

class ExtendsFinal extends BaseWithFinal {
    public function canOverride(): string {
        return "Overridden!";
    }
}

$final = new FinalClass();
echo "Final method: " . $final->method() . "\n";

$extends = new ExtendsFinal();
echo "Overridden: " . $extends->canOverride() . "\n";
echo "Final from base: " . $extends->cannotOverride() . "\n";
