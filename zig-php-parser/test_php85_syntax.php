<?php

// Arrow function
$multiply = fn($x) => $x * 2;

// Pipe operator
$result = $value |> strtoupper |> trim;

// Clone with
$newObj = clone $obj with {
    name: 'New Name',
    value: 42
};

// Try-catch-finally
try {
    throw new Exception("Test exception");
} catch (Exception $e) {
    echo $e->getMessage();
} finally {
    echo "Cleanup code";
}

// Array literals
$array = [1, 2, 3, 'hello', true, null];

// Boolean and null literals
$bool1 = true;
$bool2 = false;
$null_val = null;

// Floating point numbers
$pi = 3.14159;
$scientific = 1.5e10;
$negative_exp = 2.0E-5;

// Enhanced operators
$x += 5;
$y -= 3;
$z *= 2;
$w /= 4;
$mod %= 3;

// Null coalescing
$name = $user['name'] ?? 'Anonymous';

// Spaceship operator
$cmp = $a <=> $b;