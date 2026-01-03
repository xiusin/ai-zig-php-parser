<?php
// Functions and closures example

// Basic function
function greet(string $name, string $greeting = "Hello"): string {
    return "{$greeting}, {$name}!";
}

echo greet("World") . "\n";
echo greet("Alice", "Hi") . "\n";

// Function with variable arguments
function sum(...$numbers): int {
    return array_sum($numbers);
}

echo "Sum: " . sum(1, 2, 3, 4, 5) . "\n";

// Function with named parameters
function createUser(string $name, int $age, string $email, bool $active = true): array {
    return [
        'name' => $name,
        'age' => $age,
        'email' => $email,
        'active' => $active
    ];
}

$user = createUser(
    name: "John Doe",
    email: "john@example.com",
    age: 30
);

echo "User: " . json_encode($user) . "\n";

// Closures
$multiplier = function(int $factor) {
    return function(int $number) use ($factor) {
        return $number * $factor;
    };
};

$double = $multiplier(2);
$triple = $multiplier(3);

echo "Double 5: " . $double(5) . "\n";
echo "Triple 5: " . $triple(5) . "\n";

// Arrow functions (PHP 7.4+)
$numbers = [1, 2, 3, 4, 5];
$squared = array_map(fn($x) => $x * $x, $numbers);
echo "Squared: " . implode(", ", $squared) . "\n";

// Higher-order functions
function applyOperation(array $numbers, callable $operation): array {
    return array_map($operation, $numbers);
}

$incremented = applyOperation($numbers, fn($x) => $x + 1);
echo "Incremented: " . implode(", ", $incremented) . "\n";

// Recursive function
function factorial(int $n): int {
    if ($n <= 1) {
        return 1;
    }
    return $n * factorial($n - 1);
}

echo "Factorial of 5: " . factorial(5) . "\n";

// Function with reference parameters
function increment(int &$value): void {
    $value++;
}

$counter = 10;
increment($counter);
echo "Counter after increment: {$counter}\n";
?>