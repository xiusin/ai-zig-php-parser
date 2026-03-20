<?php
// Test 070: Static properties, singleton pattern
class Singleton {
    private static ?Singleton $instance = null;

    public string $value;

    private function __construct() {
        $this->value = 'initialized';
    }

    public static function getInstance(): Singleton {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    public static function reset(): void {
        self::$instance = null;
    }
}

class Counter {
    private static int $count = 0;
    private int $instanceId;

    public function __construct() {
        $this->instanceId = ++self::$count;
    }

    public function getId(): int {
        return $this->instanceId;
    }

    public static function getTotal(): int {
        return self::$count;
    }

    public static function reset(): void {
        self::$count = 0;
    }
}

echo "=== Singleton ===\n";
$s1 = Singleton::getInstance();
$s2 = Singleton::getInstance();
echo "s1 === s2: " . ($s1 === $s2 ? 'yes' : 'no') . "\n";
echo "s1->value: " . $s1->value . "\n";

$s1->value = 'modified';
echo "After modification, s2->value: " . $s2->value . "\n";

Singleton::reset();
$s3 = Singleton::getInstance();
echo "After reset, s3 === s1 (before reset): " . ($s3 !== $s1 ? 'yes (new instance)' : 'no') . "\n";

echo "\n=== Static counter ===\n";
Counter::reset();
$c1 = new Counter();
$c2 = new Counter();
$c3 = new Counter();
echo "c1 id: " . $c1->getId() . "\n";
echo "c2 id: " . $c2->getId() . "\n";
echo "c3 id: " . $c3->getId() . "\n";
echo "Total count: " . Counter::getTotal() . "\n";

echo "\n=== Static array ===\n";
class StaticArray {
    private static array $items = [];

    public static function add(string $item): void {
        self::$items[] = $item;
    }

    public static function getAll(): array {
        return self::$items;
    }

    public static function clear(): void {
        self::$items = [];
    }
}

StaticArray::add('first');
StaticArray::add('second');
StaticArray::add('third');
echo "Items: " . implode(', ', StaticArray::getAll()) . "\n";
StaticArray::clear();
echo "After clear: " . count(StaticArray::getAll()) . " items\n";

echo "\n=== Static with instance ===\n";
class Hybrid {
    private static int $staticCount = 0;
    private int $instanceCount;

    public function __construct() {
        $this->instanceCount = ++self::$staticCount;
    }

    public function getInstanceCount(): int {
        return $this->instanceCount;
    }

    public static function getStaticCount(): int {
        return self::$staticCount;
    }
}

$h1 = new Hybrid();
$h2 = new Hybrid();
echo "h1 instanceCount: " . $h1->getInstanceCount() . "\n";
echo "h2 instanceCount: " . $h2->getInstanceCount() . "\n";
echo "Hybrid::getStaticCount(): " . Hybrid::getStaticCount() . "\n";