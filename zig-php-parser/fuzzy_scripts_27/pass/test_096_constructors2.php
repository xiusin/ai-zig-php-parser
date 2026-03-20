<?php
// Test 096: Object instantiation with various constructors
class Constructor1 {
    public function __construct() {
        echo "Constructor1: no args\n";
    }
}

class Constructor2 {
    public function __construct(string $a) {
        echo "Constructor2: a=$a\n";
    }
}

class Constructor3 {
    public function __construct(
        public string $name,
        public int $value = 0,
        public array $tags = []
    ) {
        echo "Constructor3: name={$this->name}, value={$this->value}\n";
    }
}

class Constructor4 {
    public function __construct() {
        throw new RuntimeException("Constructor error");
    }
}

echo "=== Various constructors ===\n";
$obj1 = new Constructor1();
$obj2 = new Constructor2('arg');
$obj3 = new Constructor3('test', 42, ['a', 'b']);

echo "\n=== Named arguments ===\n";
$obj4 = new Constructor3(
    name: 'named',
    tags: ['x', 'y'],
    value: 100
);
echo "obj4 name: {$obj4->name}, value: {$obj4->value}\n";

echo "\n=== Constructor exception ===\n";
try {
    $obj5 = new Constructor4();
} catch (RuntimeException $e) {
    echo "Caught: " . $e->getMessage() . "\n";
}

echo "\n=== Factory method pattern ===\n";
class Factory {
    public static function create(string $type): object {
        return match($type) {
            'a' => new Constructor1(),
            'b' => new Constructor2('factory_arg'),
            'c' => new Constructor3('factory_created'),
            default => throw new InvalidArgumentException("Unknown type: $type"),
        };
    }
}

$factoryA = Factory::create('a');
$factoryB = Factory::create('b');
echo "Created types: " . get_class($factoryA) . ", " . get_class($factoryB) . "\n";