<?php
$factorial = function($n) use (&$factorial) {
    if ($n <= 1) {
        return 1;
    }
    return $n * $factorial($n - 1);
};

echo "Factorial of 5: " . $factorial(5) . "\n";
echo "Factorial of 10: " . $factorial(10) . "\n";

$fibonacci = function($n) use (&$fibonacci) {
    if ($n <= 1) {
        return $n;
    }
    return $fibonacci($n - 1) + $fibonacci($n - 2);
};

echo "Fibonacci of 10: " . $fibonacci(10) . "\n";
echo "Fibonacci of 15: " . $fibonacci(15) . "\n";
?>