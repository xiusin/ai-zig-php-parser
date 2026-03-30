<?php
// Test 131: Anonymous class with interface
interface AnonymousInterface {
    public function getValue(): string;
}

class UseAnonymous {
    public function create(): object {
        return new class implements AnonymousInterface {
            public string $data = 'anonymous_data';

            public function getValue(): string {
                return $this->data;
            }
        };
    }
}

echo "=== Anonymous class with interface ===\n";
$factory = new UseAnonymous();
$obj = $factory->create();
echo "Value: " . $obj->getValue() . "\n";
echo "Is AnonymousInterface: " . ($obj instanceof AnonymousInterface ? 'yes' : 'no') . "\n";