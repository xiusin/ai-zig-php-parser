<?php
abstract class Animal {
    abstract public function speak(): string;
    public function getType(): string { return static::class; }
}

class Dog extends Animal {
    public function speak(): string { return "Woof!"; }
}

class Cat extends Animal {
    public function speak(): string { return "Meow!"; }
}

class Frog extends Animal {
    public function speak(): string { return "Ribbit!"; }
}

$animals = [new Dog(), new Cat(), new Frog(), new Dog()];

foreach ($animals as $animal) {
    echo $animal->speak() . " (" . $animal->getType() . ")\n";
}

$animals = array_map(
    fn(Animal $a) => match(true) {
        $a instanceof Dog => 'Dog: ' . $a->speak(),
        $a instanceof Cat => 'Cat: ' . $a->speak(),
        default => 'Other: ' . $a->speak()
    },
    $animals
);
echo implode(' | ', $animals) . "\n";
echo "OK\n";
