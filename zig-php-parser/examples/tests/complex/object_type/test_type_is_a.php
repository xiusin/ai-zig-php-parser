<?php
class Animal {}
class Dog extends Animal {}

$dog = new Dog();

echo "is_a(dog, Dog): " . (is_a($dog, "Dog") ? "true" : "false") . "\n";
echo "is_a(dog, Animal): " . (is_a($dog, "Animal") ? "true" : "false") . "\n";
echo "is_subclass_of(dog, Dog): " . (is_subclass_of($dog, "Dog") ? "true" : "false") . "\n";
echo "is_subclass_of(dog, Animal): " . (is_subclass_of($dog, "Animal") ? "true" : "false") . "\n";
