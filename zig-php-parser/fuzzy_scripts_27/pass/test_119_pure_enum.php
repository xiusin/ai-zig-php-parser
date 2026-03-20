<?php
// Test 119: Pure enum (without backed)
enum Color {
    case Red;
    case Green;
    case Blue;

    public function hex(): string {
        return match($this) {
            self::Red => '#FF0000',
            self::Green => '#00FF00',
            self::Blue => '#0000FF',
        };
    }
}

echo "=== Pure enum ===\n";
echo "Color::Red: " . Color::Red->name . "\n";
echo "Color::Red->hex(): " . Color::Red->hex() . "\n";
echo "Color::Green->hex(): " . Color::Green->hex() . "\n";
echo "Color::Blue->hex(): " . Color::Blue->hex() . "\n";

echo "\n=== Enum cases ===\n";
foreach (Color::cases() as $case) {
    echo "  {$case->name} -> {$case->hex()}\n";
}

echo "\n=== Enum comparison ===\n";
$red1 = Color::Red;
$red2 = Color::Red;
echo "Color::Red === Color::Red: " . ($red1 === $red2 ? 'true' : 'false') . "\n";
echo "Color::Red === Color::Blue: " . ($red1 === Color::Blue ? 'true' : 'false') . "\n";