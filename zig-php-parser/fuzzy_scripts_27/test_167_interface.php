<?php
// Test 167: Interface implementation
interface Implementable {
    public function method(): string;
    public function another(): int;
}

class ImplementsInterface implements Implementable {
    public function method(): string {
        return "implemented";
    }

    public function another(): int {
        return 42;
    }
}

$obj = new ImplementsInterface();
echo "Method: " . $obj->method() . "\n";
echo "Another: " . $obj->another() . "\n";