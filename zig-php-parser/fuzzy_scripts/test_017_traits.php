<?php
// Test 017: Traits, interface inheritance, and polymorphism
trait Hello {
    public function sayHello(): string {
        return "Hello";
    }
}

trait World {
    public function sayWorld(): string {
        return "World";
    }
}

trait Combined {
    use Hello, World;

    public function sayCombined(): string {
        return $this->sayHello() . " " . $this->sayWorld() . "!";
    }
}

trait Greeting {
    protected string $greeting = "Hi";

    public function setGreeting(string $g): void {
        $this->greeting = $g;
    }

    public function getGreeting(): string {
        return $this->greeting;
    }

    abstract public function getName(): string;
}

trait NameTrait {
    public function getName(): string {
        return "Default";
    }
}

interface Animal {
    public function speak(): string;
    public function getName(): string;
}

interface Pet extends Animal {
    public function play(): string;
}

interface Wild {
    public function hunt(): string;
}

class Dog implements Pet {
    use Combined;
    private string $name;
    private static int $count = 0;

    public function __construct(string $name) {
        $this->name = $name;
        self::$count++;
    }

    public function speak(): string {
        return "Woof!";
    }

    public function getName(): string {
        return $this->name;
    }

    public function play(): string {
        return "$this->name is playing";
    }

    public static function getCount(): int {
        return self::$count;
    }
}

class Cat implements Pet, Wild {
    use Combined;

    public function __construct(private string $name) {}

    public function speak(): string {
        return "Meow!";
    }

    public function getName(): string {
        return $this->name;
    }

    public function play(): string {
        return "$this->name is playing with yarn";
    }

    public function hunt(): string {
        return "$this->name is hunting";
    }
}

class Robot implements Animal {
    public function speak(): string {
        return "Beep boop";
    }

    public function getName(): string {
        return "Robot-001";
    }
}

class Fox implements Wild {
    public function hunt(): string {
        return "Fox is hunting";
    }

    public function speak(): string {
        return "Ring-ding-ding!";
    }

    public function getName(): string {
        return "Fox";
    }
}

echo "=== Trait tests ===\n";
$dog = new Dog("Buddy");
echo "Dog says: " . $dog->sayCombined() . "\n";
echo "Dog speaks: " . $dog->speak() . "\n";
echo "Dog plays: " . $dog->play() . "\n";

$cat = new Cat("Whiskers");
echo "\nCat says: " . $cat->sayCombined() . "\n";
echo "Cat speaks: " . $cat->speak() . "\n";
echo "Cat hunts: " . $cat->hunt() . "\n";

echo "\n=== Interface type checks ===\n";
$animals = [$dog, $cat, new Robot(), new Fox()];

foreach ($animals as $animal) {
    echo get_class($animal) . ":\n";
    echo "  is Animal: " . ($animal instanceof Animal ? 'yes' : 'no') . "\n";
    echo "  is Pet: " . ($animal instanceof Pet ? 'yes' : 'no') . "\n";
    echo "  is Wild: " . ($animal instanceof Wild ? 'yes' . "\n" : 'no' . "\n");
}

echo "\n=== Static counts ===\n";
echo "Dog count: " . Dog::getCount() . "\n";

echo "\n=== Trait with abstract method ===\n";
class Person {
    use Greeting, NameTrait;
}

$p = new Person();
$p->setGreeting("Hello");
echo $p->getGreeting() . " " . $p->getName() . "!\n";

echo "\n=== Multiple trait conflict resolution ===\n";
trait A {
    public function test(): string {
        return "A";
    }
}

trait B {
    public function test(): string {
        return "B";
    }
}

class Conflict {
    use A, B {
        A::test insteadof B;
        B::test as testB;
    }

    public function run(): string {
        return "A: " . $this->test() . ", B: " . $this->testB();
    }
}

$c = new Conflict();
echo $c->run() . "\n";