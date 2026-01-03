// @syntax: go
<?php
// ============================================================================
// Go Syntax Mode Demo for zig-php
// ============================================================================
//
// This file demonstrates the Go-style syntax mode in zig-php.
// In Go mode, you can write PHP code using Go-like syntax:
//   - Variables don't need the $ prefix
//   - Property access uses . instead of ->
//   - Method calls use . instead of ->
//   - String concatenation uses + instead of .
//
// To run this file:
//   zigphp --syntax=go examples/go_syntax_demo.php
//
// Or the syntax directive at the top of the file will be detected automatically:
//   zigphp examples/go_syntax_demo.php

// ============================================================================
// 1. Variable Declarations (without $ prefix)
// ============================================================================

// In Go mode, variables are declared without the $ prefix
name = "World"
count = 42
price = 19.99
isActive = true

echo "=== Variable Declarations ===\n"
echo "name: " + name + "\n"
echo "count: " + count + "\n"
echo "price: " + price + "\n"
echo "isActive: " + isActive + "\n"
echo "\n"

// ============================================================================
// 2. String Concatenation (using + instead of .)
// ============================================================================

echo "=== String Concatenation ===\n"

firstName = "John"
lastName = "Doe"

// In Go mode, use + for string concatenation
fullName = firstName + " " + lastName
echo "Full name: " + fullName + "\n"

// Multi-part concatenation
greeting = "Hello, " + fullName + "! Welcome to zig-php."
echo greeting + "\n"
echo "\n"

// ============================================================================
// 3. Class Definition and Property Access
// ============================================================================

echo "=== Class Definition and Property Access ===\n"

class Person {
    public name
    public age
    private email
    
    function __construct(name, age, email) {
        this.name = name
        this.age = age
        this.email = email
    }
    
    function getName() {
        return this.name
    }
    
    function getAge() {
        return this.age
    }
    
    function setAge(newAge) {
        this.age = newAge
    }
    
    function getInfo() {
        // String concatenation with + in Go mode
        return "Name: " + this.name + ", Age: " + this.age
    }
}

// Create an instance
person = new Person("Alice", 30, "alice@example.com")

// Property access using . instead of ->
echo "Person name: " + person.name + "\n"
echo "Person age: " + person.age + "\n"
echo "\n"

// ============================================================================
// 4. Method Calls (using . instead of ->)
// ============================================================================

echo "=== Method Calls ===\n"

// Method calls use . instead of ->
echo "getName(): " + person.getName() + "\n"
echo "getAge(): " + person.getAge() + "\n"
echo "getInfo(): " + person.getInfo() + "\n"

// Method with parameter
person.setAge(31)
echo "After setAge(31): " + person.getAge() + "\n"
echo "\n"

// ============================================================================
// 5. Chained Method Calls
// ============================================================================

echo "=== Chained Method Calls ===\n"

class StringBuilder {
    private value
    
    function __construct() {
        this.value = ""
    }
    
    function append(str) {
        this.value = this.value + str
        return this
    }
    
    function appendLine(str) {
        this.value = this.value + str + "\n"
        return this
    }
    
    function toString() {
        return this.value
    }
}

builder = new StringBuilder()
result = builder.append("Hello").append(" ").append("World").appendLine("!").toString()
echo result
echo "\n"

// ============================================================================
// 6. Arrays and Loops
// ============================================================================

echo "=== Arrays and Loops ===\n"

numbers = [1, 2, 3, 4, 5]
echo "Numbers: "
foreach (numbers as num) {
    echo num + " "
}
echo "\n"

// Associative array
person_data = [
    "name" => "Bob",
    "age" => 25,
    "city" => "New York"
]

echo "Person data:\n"
foreach (person_data as key => value) {
    echo "  " + key + ": " + value + "\n"
}
echo "\n"

// ============================================================================
// 7. Functions
// ============================================================================

echo "=== Functions ===\n"

function greet(name) {
    return "Hello, " + name + "!"
}

function add(a, b) {
    return a + b
}

function multiply(a, b) {
    return a * b
}

echo greet("Go Mode") + "\n"
echo "add(5, 3) = " + add(5, 3) + "\n"
echo "multiply(4, 7) = " + multiply(4, 7) + "\n"
echo "\n"

// ============================================================================
// 8. Control Structures
// ============================================================================

echo "=== Control Structures ===\n"

score = 85

if (score >= 90) {
    grade = "A"
} elseif (score >= 80) {
    grade = "B"
} elseif (score >= 70) {
    grade = "C"
} else {
    grade = "F"
}

echo "Score: " + score + ", Grade: " + grade + "\n"

// While loop
echo "Countdown: "
i = 5
while (i > 0) {
    echo i + " "
    i = i - 1
}
echo "Liftoff!\n"
echo "\n"

// ============================================================================
// 9. Inheritance
// ============================================================================

echo "=== Inheritance ===\n"

class Animal {
    protected name
    
    function __construct(name) {
        this.name = name
    }
    
    function speak() {
        return "Some sound"
    }
    
    function getName() {
        return this.name
    }
}

class Dog extends Animal {
    private breed
    
    function __construct(name, breed) {
        parent::__construct(name)
        this.breed = breed
    }
    
    function speak() {
        return "Woof!"
    }
    
    function getBreed() {
        return this.breed
    }
    
    function getInfo() {
        return this.name + " is a " + this.breed
    }
}

dog = new Dog("Buddy", "Golden Retriever")
echo "Dog name: " + dog.getName() + "\n"
echo "Dog breed: " + dog.getBreed() + "\n"
echo "Dog speaks: " + dog.speak() + "\n"
echo "Dog info: " + dog.getInfo() + "\n"
echo "\n"

// ============================================================================
// 10. Static Methods and Properties
// ============================================================================

echo "=== Static Methods and Properties ===\n"

class Counter {
    private static count = 0
    
    static function increment() {
        Counter::count = Counter::count + 1
    }
    
    static function getCount() {
        return Counter::count
    }
    
    static function reset() {
        Counter::count = 0
    }
}

Counter::increment()
Counter::increment()
Counter::increment()
echo "Count after 3 increments: " + Counter::getCount() + "\n"

Counter::reset()
echo "Count after reset: " + Counter::getCount() + "\n"
echo "\n"

// ============================================================================
// Summary
// ============================================================================

echo "=== Summary ===\n"
echo "Go syntax mode provides a cleaner, more familiar syntax for developers\n"
echo "coming from Go, JavaScript, or other languages that don't use $ for variables.\n"
echo "\n"
echo "Key differences from PHP mode:\n"
echo "  - Variables: name instead of \$name\n"
echo "  - Property access: obj.prop instead of \$obj->prop\n"
echo "  - Method calls: obj.method() instead of \$obj->method()\n"
echo "  - String concat: str1 + str2 instead of \$str1 . \$str2\n"
echo "\n"
echo "Demo completed successfully!\n"
