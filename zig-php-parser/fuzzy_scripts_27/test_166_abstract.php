<?php
// Test 166: Abstract class instantiation attempt
abstract class AbstractBase {
    abstract public function method(): string;
}

class Concrete extends AbstractBase {
    public function method(): string {
        return "concrete";
    }
}

echo "=== Abstract class ===\n";
$obj = new Concrete();
echo "Method: " . $obj->method() . "\n";