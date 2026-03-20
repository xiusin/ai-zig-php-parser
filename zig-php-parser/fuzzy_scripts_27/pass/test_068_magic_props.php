<?php
// Test 068: Class property access, magic properties
class PropertyAccess {
    private array $props = [];
    private static array $staticProps = [];

    public function __get(string $name): mixed {
        return $this->props[$name] ?? "uninitialized:$name";
    }

    public function __set(string $name, mixed $value): void {
        $this->props[$name] = $value;
    }

    public function __isset(string $name): bool {
        return isset($this->props[$name]);
    }

    public function __unset(string $name): void {
        unset($this->props[$name]);
    }

    public function getProps(): array {
        return $this->props;
    }
}

class StaticMagic {
    private static array $cache = [];

    public function __set(string $name, mixed $value): void {
        self::$cache[$name] = $value;
    }

    public function __get(string $name): mixed {
        return self::$cache[$name] ?? null;
    }
}

echo "=== Magic property access ===\n";
$obj = new PropertyAccess();
echo "Before set, prop: " . $obj->prop . "\n";

$obj->prop = 'value1';
echo "After set, prop: " . $obj->prop . "\n";

$obj->another = ['a' => 1, 'b' => 2];
echo "Array prop: " . json_encode($obj->another) . "\n";

echo "isset(obj->another): " . (isset($obj->another) ? 'yes' : 'no') . "\n";

unset($obj->prop);
echo "After unset, prop: " . $obj->prop . "\n";

echo "\n=== Static magic ===\n";
$static1 = new StaticMagic();
$static2 = new StaticMagic();

$static1->shared = 'shared_value';
echo "static1->shared: " . $static1->shared . "\n";
echo "static2->shared: " . $static2->shared . "\n";

echo "\n=== Dynamic property creation ===\n";
$dynamic = new stdClass();
$dynamic->name = 'dynamic_obj';
$dynamic->value = 42;
echo "dynamic->name: " . $dynamic->name . "\n";
echo "dynamic->value: " . $dynamic->value . "\n";

$dynamic->{'computed'} = 'computed_value';
echo "dynamic->computed: " . $dynamic->computed . "\n";