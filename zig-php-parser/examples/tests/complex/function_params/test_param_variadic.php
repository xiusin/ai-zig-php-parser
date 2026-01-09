<?php
function sum(...$numbers): int {
    return array_sum($numbers);
}

function concatenate(...$strings): string {
    return implode("", $strings);
}

function mixedArgs($required, $optional = null, ...$variadic) {
    echo "Required: $required\n";
    echo "Optional: " . ($optional ?? "null") . "\n";
    echo "Variadic: " . implode(", ", $variadic) . "\n";
}

echo "Sum: " . sum(1, 2, 3, 4, 5) . "\n";
mixedArgs("A", "B", "C", "D", "E");
