<?php
// Test 160: Static method call
class StaticCall {
    public static function greet(string $name): string {
        return "Hello, $name!";
    }

    public static function add(int $a, int $b): int {
        return $a + $b;
    }
}

echo "=== Static method call ===\n";
echo StaticCall::greet('World') . "\n";
echo "Add: " . StaticCall::add(5, 3) . "\n";