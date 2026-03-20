<?php
// Test 176: Static vs instance
class StaticTest {
    public static int $static = 0;
    public int $instance = 0;

    public function __construct() {
        $this->instance = ++self::$static;
    }
}

echo "=== Static vs Instance ===\n";
$a = new StaticTest();
$b = new StaticTest();
echo "a.instance: {$a->instance}, b.instance: {$b->instance}\n";
echo "Static: " . StaticTest::$static . "\n";