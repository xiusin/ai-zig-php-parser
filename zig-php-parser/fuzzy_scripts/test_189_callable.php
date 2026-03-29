<?php
// Test 189: First-class callable
class CallableClass {
    public function add(int $a, int $b): int {
        return $a + $b;
    }
}

echo "=== First-class callable ===\n";
$obj = new CallableClass();
$add = $obj->add(...);
echo "add(5, 3): " . $add(5, 3) . "\n";