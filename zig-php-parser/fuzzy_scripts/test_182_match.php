<?php
// Test 182: Match expression
function matchDemo($value): string {
    return match($value) {
        1 => "one",
        2 => "two",
        3 => "three",
        default => "other",
    };
}

echo "=== Match expression ===\n";
echo "1: " . matchDemo(1) . "\n";
echo "5: " . matchDemo(5) . "\n";