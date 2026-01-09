<?php
// Recursive function
function factorial(int $n): int {
    if ($n <= 1) {
        return 1;
    }
    return $n * factorial($n - 1);
}

echo "Factorial of 5: " . factorial(5) . "\n";
echo "Factorial of 10: " . factorial(10) . "\n";
?>
