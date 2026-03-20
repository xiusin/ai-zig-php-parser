<?php
// Test 102: __call, __callStatic magic methods
class MagicCaller {
    public function __call(string $name, array $args): string {
        return "Called method: $name with " . count($args) . " args";
    }

    public static function __callStatic(string $name, array $args): string {
        return "Called static method: $name with " . count($args) . " args";
    }
}

class PropertyCaller {
    private array $properties = [];

    public function __get(string $name): mixed {
        return $this->properties[$name] ?? "uninitialized: $name";
    }

    public function __set(string $name, mixed $value): void {
        $this->properties[$name] = $value;
    }

    public function __isset(string $name): bool {
        return isset($this->properties[$name]);
    }

    public function __unset(string $name): void {
        unset($this->properties[$name]);
    }
}

echo "=== __call ===\n";
$obj = new MagicCaller();
echo $obj->dynamicMethod('arg1', 'arg2') . "\n";
echo $obj->anotherMethod() . "\n";

echo "\n=== __callStatic ===\n";
echo MagicCaller::staticCall('static_arg') . "\n";

echo "\n=== __get/__set ===\n";
$pc = new PropertyCaller();
echo "Before set: " . $pc->dynamic . "\n";
$pc->dynamic = 'set_value';
echo "After set: " . $pc->dynamic . "\n";

echo "\n=== __isset/__unset ===\n";
$pc->test = 'exists';
echo "isset(test): " . (isset($pc->test) ? 'yes' : 'no') . "\n";
unset($pc->test);
echo "After unset, isset(test): " . (isset($pc->test) ? 'yes' : 'no') . "\n";