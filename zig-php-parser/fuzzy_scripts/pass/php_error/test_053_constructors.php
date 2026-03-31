<?php
// Test 053: Object instantiation, constructors, and destructor
class ConstructorTest {
    public string $value;
    private static int $instanceCount = 0;

    public function __construct(string $value = 'default') {
        $this->value = $value;
        self::$instanceCount++;
        echo "Constructor called with: $value\n";
    }

    public function __destruct() {
        self::$instanceCount--;
        echo "Destructor called, remaining: " . self::$instanceCount . "\n";
    }

    public static function getCount(): int {
        return self::$instanceCount;
    }
}

class ChainedConstructor {
    public function __construct(
        public string $a,
        public int $b,
        public array $c = []
    ) {}

    public function with(string $a, int $b): array {
        return ['a' => $a, 'b' => $b, 'c' => $this->c];
    }
}

echo "=== Constructor tests ===\n";
echo "Initial count: " . ConstructorTest::getCount() . "\n";

$obj1 = new ConstructorTest('first');
echo "After obj1: " . ConstructorTest::getCount() . "\n";

$obj2 = new ConstructorTest('second');
echo "After obj2: " . ConstructorTest::getCount() . "\n";

$obj3 = new ConstructorTest();
echo "After obj3 (default): " . ConstructorTest::getCount() . "\n";

echo "\n=== Chained constructor ===\n";
$chained = new ChainedConstructor('A', 1, ['x']);
echo "Initial: a={$chained->a}, b={$chained->b}\n";
$result = $chained->with('B', 2);
echo "With: a={$result['a']}, b={$result['b']}\n";

echo "\n=== Unset objects ===\n";
unset($obj1);
echo "After unset obj1: " . ConstructorTest::getCount() . "\n";

echo "\n=== Multiple references ===\n";
$ref1 = new ConstructorTest('ref1');
$ref2 = $ref1;
$ref3 = &$ref2;
echo "After ref2=$ref1, ref3=&ref2: " . ConstructorTest::getCount() . "\n";

unset($ref1);
echo "After unset ref1: " . ConstructorTest::getCount() . "\n";
unset($ref2);
echo "After unset ref2: " . ConstructorTest::getCount() . "\n";
unset($ref3);
echo "After unset ref3: " . ConstructorTest::getCount() . "\n";