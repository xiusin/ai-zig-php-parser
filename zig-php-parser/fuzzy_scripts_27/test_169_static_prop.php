<?php
// Test 169: Static property access
class StaticProp {
    public static int $counter = 0;

    public function __construct() {
        self::$counter++;
    }

    public static function getCounter(): int {
        return self::$counter;
    }
}

echo "=== Static property ===\n";
new StaticProp();
new StaticProp();
new StaticProp();
echo "Counter: " . StaticProp::$counter . "\n";
echo "getCounter: " . StaticProp::getCounter() . "\n";