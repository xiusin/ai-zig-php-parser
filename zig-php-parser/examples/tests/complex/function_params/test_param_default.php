<?php
function greet($name = "World", $greeting = "Hello") {
    return "$greeting, $name!";
}

echo greet() . "\n";
echo greet("Alice") . "\n";
echo greet("Bob", "Hi") . "\n";
echo greet("Charlie", "Good morning") . "\n";
