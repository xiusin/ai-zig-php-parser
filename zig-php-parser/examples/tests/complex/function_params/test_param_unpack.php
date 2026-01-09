<?php
function sum($a, $b, $c) {
    return $a + $b + $c;
}

$numbers = [1, 2, 3];
echo "Sum: " . sum(...$numbers) . "\n";

function logMessage($level, $message, $context = []) {
    echo "[$level] $message\n";
    if (!empty($context)) {
        echo "Context: " . json_encode($context) . "\n";
    }
}

$context = ["user" => "Alice", "action" => "login"];
logMessage("INFO", "User logged in", ...$context);
